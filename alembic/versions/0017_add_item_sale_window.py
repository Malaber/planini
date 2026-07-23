"""add item sale window

Revision ID: 0017_add_item_sale_window
Revises: 0016_add_multi_use_invites
Create Date: 2026-07-23
"""

from alembic import op
import sqlalchemy as sa


revision = "0017_add_item_sale_window"
down_revision = "0016_add_multi_use_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "grocery_items",
        sa.Column("sale_starts_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "grocery_items",
        sa.Column("sale_ends_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("grocery_items", "sale_ends_at")
    op.drop_column("grocery_items", "sale_starts_at")
