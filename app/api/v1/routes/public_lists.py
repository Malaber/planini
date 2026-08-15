from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.routes.items import (
    CHECKED_ITEMS_PAGE_SIZE,
    _broadcast,
    _checked_item_count,
    _checked_items_page,
    _validate_category_id,
)
from app.api.v1.routes.lists import _open_item_count, _serialize_list
from app.api.v1.routes.public_list_links import _as_utc, get_valid_public_list_link
from app.core.database import get_db
from app.models import (
    Category,
    GroceryItem,
    GroceryList,
    ListCategoryOrder,
    ListDisabledCategory,
    PublicListLink,
)
from app.schemas.domain import (
    CategoryOut,
    GroceryItemCreate,
    GroceryItemOut,
    GroceryItemsWindowOut,
    GroceryItemUpdate,
    PublicGroceryListOut,
    ListCategoryOrderOut,
    ListDisabledCategoriesOut,
)

router = APIRouter(prefix="/public/lists", tags=["public-lists"])


async def _public_list(db: AsyncSession, token: str) -> GroceryList:
    grocery_list, _ = await _public_list_with_link(db, token)
    return grocery_list


async def _public_list_with_link(
    db: AsyncSession, token: str
) -> tuple[GroceryList, PublicListLink]:
    link = await get_valid_public_list_link(db, token)
    result = await db.execute(select(GroceryList).where(GroceryList.id == link.list_id))
    grocery_list = result.scalar_one_or_none()
    if grocery_list is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return grocery_list, link


async def _public_item(
    db: AsyncSession, token: str, item_id: UUID
) -> tuple[GroceryList, GroceryItem]:
    grocery_list = await _public_list(db, token)
    result = await db.execute(
        select(GroceryItem).where(GroceryItem.id == item_id, GroceryItem.list_id == grocery_list.id)
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return grocery_list, item


@router.get("/{token}", response_model=PublicGroceryListOut)
async def get_public_list(token: str, db: AsyncSession = Depends(get_db)) -> PublicGroceryListOut:
    grocery_list, link = await _public_list_with_link(db, token)
    serialized = _serialize_list(grocery_list, await _open_item_count(db, grocery_list.id))
    return PublicGroceryListOut(**serialized.model_dump(), expires_at=_as_utc(link.expires_at))


@router.get("/{token}/categories", response_model=list[CategoryOut])
async def get_public_categories(token: str, db: AsyncSession = Depends(get_db)) -> list[Category]:
    grocery_list = await _public_list(db, token)
    result = await db.execute(
        select(Category)
        .where(
            (Category.household_id.is_(None)) | (Category.household_id == grocery_list.household_id)
        )
        .order_by(Category.name.asc())
    )
    return list(result.scalars().all())


@router.get("/{token}/category-order", response_model=list[ListCategoryOrderOut])
async def get_public_category_order(
    token: str, db: AsyncSession = Depends(get_db)
) -> list[ListCategoryOrder]:
    grocery_list = await _public_list(db, token)
    result = await db.execute(
        select(ListCategoryOrder)
        .where(ListCategoryOrder.list_id == grocery_list.id)
        .order_by(ListCategoryOrder.sort_order.asc(), ListCategoryOrder.category_id.asc())
    )
    return list(result.scalars().all())


@router.get("/{token}/disabled-categories", response_model=ListDisabledCategoriesOut)
async def get_public_disabled_categories(
    token: str, db: AsyncSession = Depends(get_db)
) -> ListDisabledCategoriesOut:
    grocery_list = await _public_list(db, token)
    result = await db.execute(
        select(ListDisabledCategory)
        .where(ListDisabledCategory.list_id == grocery_list.id)
        .order_by(ListDisabledCategory.category_id.asc())
    )
    return ListDisabledCategoriesOut(
        category_ids=[entry.category_id for entry in result.scalars().all()]
    )


@router.get("/{token}/items/window", response_model=GroceryItemsWindowOut)
async def public_item_window(
    token: str, db: AsyncSession = Depends(get_db)
) -> GroceryItemsWindowOut:
    grocery_list = await _public_list(db, token)
    active_result = await db.execute(
        select(GroceryItem).where(
            GroceryItem.list_id == grocery_list.id, GroceryItem.checked.is_(False)
        )
    )
    checked_items = await _checked_items_page(db, grocery_list.id, offset=0, limit=10)
    checked_count = await _checked_item_count(db, grocery_list.id)
    return GroceryItemsWindowOut(
        items=[
            GroceryItemOut.model_validate(item)
            for item in [*active_result.scalars().all(), *checked_items]
        ],
        checked_remaining_count=max(checked_count - len(checked_items), 0),
    )


@router.get("/{token}/items/checked", response_model=list[GroceryItemOut])
async def public_checked_items(
    token: str,
    offset: int = Query(0, ge=0),
    limit: int = Query(CHECKED_ITEMS_PAGE_SIZE, ge=1, le=CHECKED_ITEMS_PAGE_SIZE),
    db: AsyncSession = Depends(get_db),
) -> list[GroceryItem]:
    grocery_list = await _public_list(db, token)
    return await _checked_items_page(db, grocery_list.id, offset=offset, limit=limit)


@router.post("/{token}/items", response_model=GroceryItemOut)
async def create_public_item(
    token: str, payload: GroceryItemCreate, db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    grocery_list = await _public_list(db, token)
    await _validate_category_id(db, grocery_list, payload.category_id)
    actor_id = grocery_list.created_by
    item = GroceryItem(
        list_id=grocery_list.id,
        name=payload.name,
        quantity_text=payload.quantity_text,
        note=payload.note,
        category_id=payload.category_id,
        sort_order=payload.sort_order,
        created_by=actor_id,
        updated_by=actor_id,
        checked_state_recorded_at=datetime.now(UTC),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_created", actor_id, item)
    return item


@router.patch("/{token}/items/{item_id}", response_model=GroceryItemOut)
async def update_public_item(
    token: str, item_id: UUID, payload: GroceryItemUpdate, db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    grocery_list, item = await _public_item(db, token, item_id)
    if payload.list_id is not None and payload.list_id != grocery_list.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Public links can only edit this list."
        )
    await _validate_category_id(
        db, grocery_list, payload.category_id if "category_id" in payload.model_fields_set else None
    )
    for key, value in payload.model_dump(exclude_unset=True, exclude={"list_id"}).items():
        setattr(item, key, value)
    item.updated_by = grocery_list.created_by
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_updated", grocery_list.created_by, item)
    return item


@router.post("/{token}/items/{item_id}/check", response_model=GroceryItemOut)
async def check_public_item(
    token: str, item_id: UUID, db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    grocery_list, item = await _public_item(db, token, item_id)
    recorded_at = datetime.now(UTC)
    item.checked = True
    item.checked_at = recorded_at
    item.checked_state_recorded_at = recorded_at
    item.hidden_until = None
    item.checked_by = grocery_list.created_by
    item.updated_by = grocery_list.created_by
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_checked", grocery_list.created_by, item)
    return item


@router.post("/{token}/items/{item_id}/uncheck", response_model=GroceryItemOut)
async def uncheck_public_item(
    token: str, item_id: UUID, db: AsyncSession = Depends(get_db)
) -> GroceryItem:
    grocery_list, item = await _public_item(db, token, item_id)
    item.checked = False
    item.checked_at = None
    item.checked_state_recorded_at = datetime.now(UTC)
    item.hidden_until = None
    item.checked_by = None
    item.updated_by = grocery_list.created_by
    await db.commit()
    await db.refresh(item)
    await _broadcast("item_unchecked", grocery_list.created_by, item)
    return item


@router.delete("/{token}/items/{item_id}")
async def delete_public_item(
    token: str, item_id: UUID, db: AsyncSession = Depends(get_db)
) -> dict[str, str]:
    grocery_list, item = await _public_item(db, token, item_id)
    await db.delete(item)
    await db.commit()
    from app.api.v1.routes.items import _broadcast_deleted

    await _broadcast_deleted(grocery_list.id, grocery_list.created_by, item.id)
    return {"message": "deleted"}
