from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_list_for_editor, get_list_for_user
from app.core.database import get_db
from app.models import Category, GroceryItem, GroceryList, ListDisabledCategory, User
from app.schemas.domain import (
    GroceryItemCreate,
    GroceryItemOfflineSyncIn,
    GroceryItemOfflineSyncOut,
    GroceryItemOut,
    GroceryItemsWindowOut,
    GroceryItemUpdate,
)
from app.services.websocket_hub import hub

router = APIRouter(tags=["items"])

CHECKED_ITEMS_INITIAL_LIMIT = 10
CHECKED_ITEMS_PAGE_SIZE = 100


async def _broadcast(event_type: str, user_id: UUID, item: GroceryItem) -> None:
    await hub.broadcast(
        item.list_id,
        {
            "type": event_type,
            "list_id": str(item.list_id),
            "timestamp": datetime.now(UTC).isoformat(),
            "actor_user_id": str(user_id),
            "payload": {"item": GroceryItemOut.model_validate(item).model_dump(mode="json")},
        },
    )


async def _broadcast_deleted(list_id: UUID, user_id: UUID, item_id: UUID) -> None:
    await hub.broadcast(
        list_id,
        {
            "type": "item_deleted",
            "list_id": str(list_id),
            "timestamp": datetime.now(UTC).isoformat(),
            "actor_user_id": str(user_id),
            "payload": {"item": {"id": str(item_id)}},
        },
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _payload_model(model, payload: dict[str, object | None] | None):
    try:
        return model.model_validate(payload or {})
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=exc.errors(),
        ) from exc


def _checked_state_recorded_at(item: GroceryItem) -> datetime:
    fallback = datetime.min.replace(tzinfo=UTC)
    return _as_utc(item.checked_state_recorded_at or item.checked_at or item.updated_at or fallback)


async def _validate_category_id(
    db: AsyncSession, grocery_list: GroceryList, category_id: UUID | None
) -> None:
    if category_id is None:
        return

    result = await db.execute(
        select(Category.id).where(
            Category.id == category_id,
            (Category.household_id.is_(None))
            | (Category.household_id == grocery_list.household_id),
        )
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Selected category does not exist.",
        )

    disabled_result = await db.execute(
        select(ListDisabledCategory.id).where(
            ListDisabledCategory.list_id == grocery_list.id,
            ListDisabledCategory.category_id == category_id,
        )
    )
    if disabled_result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Selected category is disabled for this list.",
        )


async def _checked_item_count(db: AsyncSession, list_id: UUID) -> int:
    result = await db.execute(
        select(func.count())
        .select_from(GroceryItem)
        .where(
            GroceryItem.list_id == list_id,
            GroceryItem.checked.is_(True),
        )
    )
    return int(result.scalar_one())


async def _checked_items_page(
    db: AsyncSession, list_id: UUID, *, offset: int, limit: int
) -> list[GroceryItem]:
    result = await db.execute(
        select(GroceryItem)
        .where(GroceryItem.list_id == list_id, GroceryItem.checked.is_(True))
        .order_by(GroceryItem.checked_at.desc(), GroceryItem.name.asc())
        .offset(offset)
        .limit(limit)
    )
    return list(result.scalars().all())


async def _sync_item_for_mutation(
    db: AsyncSession,
    list_id: UUID,
    item_id: UUID | str | None,
    client_item_ids: dict[str, UUID],
) -> GroceryItem | None:
    if item_id is None:
        return None

    resolved_item_id = client_item_ids.get(str(item_id))
    if resolved_item_id is None:
        try:
            resolved_item_id = UUID(str(item_id))
        except ValueError:
            return None

    result = await db.execute(
        select(GroceryItem).where(
            GroceryItem.id == resolved_item_id,
            GroceryItem.list_id == list_id,
        )
    )
    return result.scalar_one_or_none()


@router.post("/lists/{list_id}/items", response_model=GroceryItemOut)
async def create_item(
    list_id: UUID,
    payload: GroceryItemCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> GroceryItem:
    grocery_list = await get_list_for_editor(db, list_id, user.id)
    await _validate_category_id(db, grocery_list, payload.category_id)
    item = GroceryItem(
        list_id=list_id,
        name=payload.name,
        quantity_text=payload.quantity_text,
        note=payload.note,
        category_id=payload.category_id,
        sort_order=payload.sort_order,
        created_by=user.id,
        updated_by=user.id,
        checked_state_recorded_at=datetime.now(UTC),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_created", user.id, item)
    return item


@router.get("/lists/{list_id}/items", response_model=list[GroceryItemOut])
async def list_items(
    list_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[GroceryItem]:
    await get_list_for_user(db, list_id, user.id)
    result = await db.execute(select(GroceryItem).where(GroceryItem.list_id == list_id))
    return list(result.scalars().all())


@router.get("/lists/{list_id}/items/window", response_model=GroceryItemsWindowOut)
async def list_item_window(
    list_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> GroceryItemsWindowOut:
    await get_list_for_user(db, list_id, user.id)
    active_result = await db.execute(
        select(GroceryItem).where(GroceryItem.list_id == list_id, GroceryItem.checked.is_(False))
    )
    checked_items = await _checked_items_page(
        db, list_id, offset=0, limit=CHECKED_ITEMS_INITIAL_LIMIT
    )
    checked_count = await _checked_item_count(db, list_id)
    items = list(active_result.scalars().all()) + checked_items
    return GroceryItemsWindowOut(
        items=[GroceryItemOut.model_validate(item) for item in items],
        checked_remaining_count=max(checked_count - len(checked_items), 0),
    )


@router.get("/lists/{list_id}/items/checked", response_model=list[GroceryItemOut])
async def list_checked_items(
    list_id: UUID,
    offset: int = Query(0, ge=0),
    limit: int = Query(CHECKED_ITEMS_PAGE_SIZE, ge=1, le=CHECKED_ITEMS_PAGE_SIZE),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[GroceryItem]:
    await get_list_for_user(db, list_id, user.id)
    return await _checked_items_page(db, list_id, offset=offset, limit=limit)


@router.patch("/items/{item_id}", response_model=GroceryItemOut)
async def update_item(
    item_id: UUID,
    payload: GroceryItemUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> GroceryItem:
    result = await db.execute(select(GroceryItem).where(GroceryItem.id == item_id))
    item = result.scalar_one()
    source_list = await get_list_for_editor(db, item.list_id, user.id)
    target_list = source_list
    is_moving_lists = payload.list_id is not None and payload.list_id != item.list_id
    if is_moving_lists:
        target_list = await get_list_for_editor(db, payload.list_id, user.id)
        if target_list.household_id != source_list.household_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Items can only move between lists in the same household.",
            )
    await _validate_category_id(
        db,
        target_list,
        payload.category_id if "category_id" in payload.model_fields_set else None,
    )
    for key, value in payload.model_dump(exclude_unset=True, exclude={"list_id"}).items():
        setattr(item, key, value)
    item.list_id = target_list.id
    item.updated_by = user.id
    await db.commit()
    await db.refresh(item)
    if is_moving_lists:
        await _broadcast_deleted(source_list.id, user.id, item.id)
        await _broadcast("item_created", user.id, item)
    else:
        await _broadcast("item_updated", user.id, item)
    return item


@router.post("/items/{item_id}/check", response_model=GroceryItemOut)
async def check_item(
    item_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    result = await db.execute(select(GroceryItem).where(GroceryItem.id == item_id))
    item = result.scalar_one()
    await get_list_for_editor(db, item.list_id, user.id)
    item.checked = True
    recorded_at = datetime.now(UTC)
    item.checked_at = recorded_at
    item.checked_state_recorded_at = recorded_at
    item.hidden_until = None
    item.checked_by = user.id
    item.updated_by = user.id
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_checked", user.id, item)
    return item


@router.post("/items/{item_id}/uncheck", response_model=GroceryItemOut)
async def uncheck_item(
    item_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    result = await db.execute(select(GroceryItem).where(GroceryItem.id == item_id))
    item = result.scalar_one()
    await get_list_for_editor(db, item.list_id, user.id)
    item.checked = False
    item.checked_at = None
    item.checked_state_recorded_at = datetime.now(UTC)
    item.hidden_until = None
    item.checked_by = None
    item.updated_by = user.id
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_unchecked", user.id, item)
    return item


@router.post("/lists/{list_id}/items/sync", response_model=GroceryItemOfflineSyncOut)
async def sync_offline_items(
    list_id: UUID,
    payload: GroceryItemOfflineSyncIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> GroceryItemOfflineSyncOut:
    grocery_list = await get_list_for_editor(db, list_id, user.id)
    client_item_ids: dict[str, UUID] = {}
    changed_items: dict[UUID, GroceryItem] = {}
    deleted_item_ids: list[str] = []
    deleted_item_id_set: set[UUID] = set()
    broadcasts: list[tuple[str, GroceryItem | UUID]] = []
    seen_mutation_ids: set[str] = set()
    applied_mutation_ids: list[str] = []

    for mutation in payload.mutations:
        if mutation.mutation_id in seen_mutation_ids:
            continue
        seen_mutation_ids.add(mutation.mutation_id)
        recorded_at = _as_utc(mutation.recorded_at)
        event_type: str | None = None
        item: GroceryItem | None = None

        if mutation.type == "create":
            create_payload = _payload_model(GroceryItemCreate, mutation.payload)
            await _validate_category_id(db, grocery_list, create_payload.category_id)
            if mutation.client_item_id:
                existing_result = await db.execute(
                    select(GroceryItem).where(
                        GroceryItem.list_id == list_id,
                        GroceryItem.client_created_id == mutation.client_item_id,
                    )
                )
                item = existing_result.scalar_one_or_none()
            if item is None:
                item = GroceryItem(
                    list_id=list_id,
                    name=create_payload.name,
                    quantity_text=create_payload.quantity_text,
                    note=create_payload.note,
                    category_id=create_payload.category_id,
                    sort_order=create_payload.sort_order,
                    created_by=user.id,
                    updated_by=user.id,
                    checked_state_recorded_at=recorded_at,
                    client_created_id=mutation.client_item_id,
                )
                db.add(item)
                await db.flush()
                event_type = "item_created"
            if mutation.client_item_id:
                client_item_ids[mutation.client_item_id] = item.id
            changed_items[item.id] = item

        elif mutation.type == "update":
            update_payload = _payload_model(GroceryItemUpdate, mutation.payload)
            await _validate_category_id(
                db,
                grocery_list,
                (
                    update_payload.category_id
                    if "category_id" in update_payload.model_fields_set
                    else None
                ),
            )
            item = await _sync_item_for_mutation(db, list_id, mutation.item_id, client_item_ids)
            if item is not None:
                for key, value in update_payload.model_dump(exclude_unset=True).items():
                    setattr(item, key, value)
                item.updated_by = user.id
                changed_items[item.id] = item
                event_type = "item_updated"

        elif mutation.type == "set_checked":
            if mutation.checked is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail="Offline checked mutations require a checked value.",
                )
            item = await _sync_item_for_mutation(db, list_id, mutation.item_id, client_item_ids)
            if item is not None:
                changed_items[item.id] = item
                if recorded_at >= _checked_state_recorded_at(item):
                    item.checked = mutation.checked
                    item.checked_at = recorded_at if mutation.checked else None
                    item.checked_state_recorded_at = recorded_at
                    item.hidden_until = None
                    item.checked_by = user.id if mutation.checked else None
                    item.updated_by = user.id
                    event_type = "item_checked" if mutation.checked else "item_unchecked"

        elif mutation.type == "delete":
            item = await _sync_item_for_mutation(db, list_id, mutation.item_id, client_item_ids)
            if item is not None:
                deleted_item_id_set.add(item.id)
                deleted_item_ids.append(str(item.id))
                broadcasts.append(("item_deleted", item.id))
                await db.delete(item)

        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unknown offline mutation type: {mutation.type}",
            )

        if event_type is not None and item is not None:
            broadcasts.append((event_type, item))
        applied_mutation_ids.append(mutation.mutation_id)

    await db.commit()

    synced_items: list[GroceryItemOut] = []
    for item_id, item in changed_items.items():
        if item_id in deleted_item_id_set:
            continue
        await db.refresh(item)
        synced_items.append(GroceryItemOut.model_validate(item))

    for event_type, event_payload in broadcasts:
        if event_type == "item_deleted" and isinstance(event_payload, UUID):
            await _broadcast_deleted(list_id, user.id, event_payload)
        elif isinstance(event_payload, GroceryItem) and event_payload.id not in deleted_item_id_set:
            await _broadcast(event_type, user.id, event_payload)

    return GroceryItemOfflineSyncOut(
        items=synced_items,
        deleted_item_ids=deleted_item_ids,
        client_item_ids=client_item_ids,
        applied_mutation_ids=applied_mutation_ids,
    )


@router.delete("/items/{item_id}")
async def delete_item(
    item_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> dict[str, str]:
    result = await db.execute(select(GroceryItem).where(GroceryItem.id == item_id))
    item = result.scalar_one()
    await get_list_for_editor(db, item.list_id, user.id)
    await db.delete(item)
    await db.commit()
    await _broadcast_deleted(item.list_id, user.id, item.id)
    return {"message": "deleted"}
