from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import func, select

from app.api.deps import ensure_non_admin_user, get_current_user, get_list_for_user
from app.core.database import get_db
from app.models import GroceryItem, ListCategoryOrder, ListDisabledCategory
from app.schemas.domain import GroceryItemOut, ListCategoryOrderOut
from app.services.websocket_hub import hub

router = APIRouter(tags=["websocket"])

CHECKED_ITEMS_INITIAL_LIMIT = 10


async def _checked_item_count(db, list_id: UUID) -> int:
    result = await db.execute(
        select(func.count())
        .select_from(GroceryItem)
        .where(
            GroceryItem.list_id == list_id,
            GroceryItem.checked.is_(True),
        )
    )
    return int(result.scalar_one())


async def _snapshot_items(db, list_id: UUID) -> tuple[list[dict[str, object]], int]:
    active_result = await db.execute(
        select(GroceryItem).where(GroceryItem.list_id == list_id, GroceryItem.checked.is_(False))
    )
    checked_result = await db.execute(
        select(GroceryItem)
        .where(GroceryItem.list_id == list_id, GroceryItem.checked.is_(True))
        .order_by(GroceryItem.checked_at.desc(), GroceryItem.name.asc())
        .limit(CHECKED_ITEMS_INITIAL_LIMIT)
    )
    active_items = list(active_result.scalars().all())
    checked_items = list(checked_result.scalars().all())
    checked_count = await _checked_item_count(db, list_id)
    snapshot = [
        GroceryItemOut.model_validate(row).model_dump(mode="json")
        for row in [*active_items, *checked_items]
    ]
    return snapshot, max(checked_count - len(checked_items), 0)


@router.websocket("/ws/lists/{list_id}")
async def ws_list(websocket: WebSocket, list_id: UUID) -> None:
    db_gen = get_db()
    db = await anext(db_gen)
    try:
        user = await get_current_user(websocket, db, websocket.query_params.get("token"))
        ensure_non_admin_user(user)
        await get_list_for_user(db, list_id, user.id)
        await hub.connect(list_id, websocket, user.id)
        snapshot, checked_remaining_count = await _snapshot_items(db, list_id)
        category_order_result = await db.execute(
            select(ListCategoryOrder)
            .where(ListCategoryOrder.list_id == list_id)
            .order_by(ListCategoryOrder.sort_order.asc(), ListCategoryOrder.category_id.asc())
        )
        category_order = [
            ListCategoryOrderOut(category_id=row.category_id, sort_order=row.sort_order).model_dump(
                mode="json"
            )
            for row in category_order_result.scalars()
        ]
        disabled_category_result = await db.execute(
            select(ListDisabledCategory)
            .where(ListDisabledCategory.list_id == list_id)
            .order_by(ListDisabledCategory.category_id.asc())
        )
        disabled_category_ids = [str(row.category_id) for row in disabled_category_result.scalars()]
        await websocket.send_json(
            {
                "type": "list_snapshot",
                "list_id": str(list_id),
                "timestamp": datetime.now(UTC).isoformat(),
                "actor_user_id": str(user.id),
                "payload": {
                    "items": snapshot,
                    "checked_remaining_count": checked_remaining_count,
                    "category_order": category_order,
                    "disabled_category_ids": disabled_category_ids,
                },
            }
        )
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        hub.disconnect(list_id, websocket)
    finally:
        await db_gen.aclose()
