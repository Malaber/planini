from app.models import Category
from app.schemas.domain import CategoryOut


def localized_category(category: Category, locale: str) -> CategoryOut:
    return CategoryOut(
        id=category.id,
        household_id=category.household_id,
        name=category.localized_name(locale),
        color=category.color,
        aliases=category.aliases,
        translations=category.translations,
    )
