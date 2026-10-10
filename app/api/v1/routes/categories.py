from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import Category, GroceryItem, ListCategoryOrder, ListDisabledCategory
from app.schemas.domain import CategoryCreate, CategoryOut

router = APIRouter(tags=["categories"])


@router.post("/categories", response_model=CategoryOut)
async def create_category(
    payload: CategoryCreate,
    _: object = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Category:
    category = Category(
        household_id=None,
        name=payload.name,
        color=payload.color,
    )
    category.aliases = payload.aliases
    category.translations = payload.translations
    db.add(category)
    await db.commit()
    await db.refresh(category)
    return category


@router.get("/categories", response_model=list[CategoryOut])
async def list_categories(
    _: object = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Category]:
    result = await db.execute(select(Category).order_by(Category.name.asc()))
    return list(result.scalars().all())


@router.patch("/categories/{category_id}", response_model=CategoryOut)
async def update_category(
    category_id: UUID,
    payload: CategoryCreate,
    _: object = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Category:
    result = await db.execute(select(Category).where(Category.id == category_id))
    category = result.scalar_one()
    category.name = payload.name
    category.color = payload.color
    category.aliases = payload.aliases
    category.translations = payload.translations
    await db.commit()
    await db.refresh(category)
    return category


@router.delete("/categories/{category_id}")
async def delete_category(
    category_id: UUID,
    _: object = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    result = await db.execute(select(Category).where(Category.id == category_id))
    category = result.scalar_one()
    item_result = await db.execute(
        select(GroceryItem).where(GroceryItem.category_id == category_id)
    )
    for item in item_result.scalars().all():
        item.category_id = None

    order_result = await db.execute(
        select(ListCategoryOrder).where(ListCategoryOrder.category_id == category_id)
    )
    for order in order_result.scalars().all():
        await db.delete(order)

    disabled_result = await db.execute(
        select(ListDisabledCategory).where(ListDisabledCategory.category_id == category_id)
    )
    for disabled in disabled_result.scalars().all():
        await db.delete(disabled)

    await db.delete(category)
    await db.commit()
    return {"message": "deleted"}
