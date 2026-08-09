"""add offline item sync metadata

Revision ID: 0012_add_offline_item_sync
Revises: 0011_add_passkey_reset_links
Create Date: 2026-05-14
"""

from alembic import op
import sqlalchemy as sa

revision = "0012_add_offline_item_sync"
down_revision = "0011_add_passkey_reset_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "grocery_items",
        sa.Column("checked_state_recorded_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "grocery_items", sa.Column("client_created_id", sa.String(length=120), nullable=True)
    )
    op.execute("""
        UPDATE grocery_items
        SET checked_state_recorded_at = COALESCE(checked_at, updated_at, created_at)
        """)
    op.create_index(
        "ix_grocery_items_list_client_created_id",
        "grocery_items",
        ["list_id", "client_created_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_grocery_items_list_client_created_id", table_name="grocery_items")
    op.drop_column("grocery_items", "client_created_id")
    op.drop_column("grocery_items", "checked_state_recorded_at")
