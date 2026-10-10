"""add item hidden until

Revision ID: 0013_add_item_hidden_until
Revises: 0012_add_offline_item_sync
Create Date: 2026-05-14
"""

from alembic import op
import sqlalchemy as sa

revision = "0013_add_item_hidden_until"
down_revision = "0012_add_offline_item_sync"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "grocery_items",
        sa.Column("hidden_until", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("grocery_items", "hidden_until")
