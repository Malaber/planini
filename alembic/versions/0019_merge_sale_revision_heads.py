"""merge sale and category migration paths

Revision ID: 0019_merge_sale_revision_heads
Revises: 0018_add_category_translations, 0018_add_item_sale_window,
         0017_add_item_sale_window
Create Date: 2026-08-08
"""

revision = "0019_merge_sale_revision_heads"
down_revision = (
    "0018_add_category_translations",
    "0018_add_item_sale_window",
    "0017_add_item_sale_window",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
