"""add item sale window

Revision ID: 0018_add_item_sale_window
Revises: 0017_add_list_accent_color
Create Date: 2026-07-23
"""

from alembic import op
import sqlalchemy as sa

revision = "0018_add_item_sale_window"
down_revision = "0017_add_list_accent_color"
branch_labels = None
depends_on = None


def upgrade() -> None:
    column_names = {
        column["name"] for column in sa.inspect(op.get_bind()).get_columns("grocery_items")
    }
    if "sale_starts_at" not in column_names:
        op.add_column(
            "grocery_items",
            sa.Column("sale_starts_at", sa.DateTime(timezone=True), nullable=True),
        )
    if "sale_ends_at" not in column_names:
        op.add_column(
            "grocery_items",
            sa.Column("sale_ends_at", sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    column_names = {
        column["name"] for column in sa.inspect(op.get_bind()).get_columns("grocery_items")
    }
    if "sale_ends_at" in column_names:
        op.drop_column("grocery_items", "sale_ends_at")
    if "sale_starts_at" in column_names:
        op.drop_column("grocery_items", "sale_starts_at")
