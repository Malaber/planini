"""add category translations

Revision ID: 0018_add_category_translations
Revises: 0017_add_list_accent_color
Create Date: 2026-07-24
"""

import json

from alembic import op
import sqlalchemy as sa

revision = "0018_add_category_translations"
down_revision = "0017_add_list_accent_color"
branch_labels = None
depends_on = None


DEFAULT_CATEGORY_TRANSLATIONS = {
    "Konserven": ("Canned Goods", "Konserven"),
    "Milch & Eier": ("Dairy & Eggs", "Milch & Eier"),
    "Nudeln": ("Pasta", "Nudeln"),
    "Reinigung": ("Cleaning", "Reinigung"),
    "Tiefkuehlkost": ("Frozen Foods", "Tiefkühlkost"),
    "Vegan": ("Vegan", "Vegan"),
    "Backwaren": ("Bakery", "Backwaren"),
    "Backzutaten": ("Baking Supplies", "Backzutaten"),
    "Fleisch": ("Meat", "Fleisch"),
    "Gemuese": ("Produce", "Gemüse"),
    "Haushalt": ("Household", "Haushalt"),
    "Weekend chores": ("Weekend Chores", "Wochenendaufgaben"),
}


def upgrade() -> None:
    op.add_column(
        "categories",
        sa.Column("translations_text", sa.Text(), nullable=False, server_default="{}"),
    )
    categories = sa.table(
        "categories",
        sa.column("name", sa.String(length=120)),
        sa.column("translations_text", sa.Text()),
    )
    for old_name, (english_name, german_name) in DEFAULT_CATEGORY_TRANSLATIONS.items():
        op.execute(
            categories.update()
            .where(categories.c.name == old_name)
            .values(
                name=english_name,
                translations_text=json.dumps(
                    {"de": german_name}, ensure_ascii=False, sort_keys=True
                ),
            )
        )


def downgrade() -> None:
    categories = sa.table(
        "categories",
        sa.column("name", sa.String(length=120)),
        sa.column("translations_text", sa.Text()),
    )
    for old_name, (english_name, german_name) in DEFAULT_CATEGORY_TRANSLATIONS.items():
        op.execute(
            categories.update()
            .where(categories.c.name == english_name)
            .where(categories.c.translations_text.contains(f'"de": "{german_name}"'))
            .values(name=old_name)
        )
    op.drop_column("categories", "translations_text")
