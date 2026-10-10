"""drop global category sort order

Revision ID: 0005_drop_category_sort_order
Revises: 0004_add_list_category_orders
Create Date: 2026-03-18
"""

from alembic import op
import sqlalchemy as sa

revision = "0005_drop_category_sort_order"
down_revision = "0004_add_list_category_orders"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("categories", "sort_order")


def downgrade() -> None:
    op.add_column(
        "categories",
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    op.alter_column("categories", "sort_order", server_default=None)
