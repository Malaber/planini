"""add category aliases

Revision ID: 0006_add_category_aliases
Revises: 0005_drop_category_sort_order
Create Date: 2026-03-18
"""

from alembic import op
import sqlalchemy as sa

revision = "0006_add_category_aliases"
down_revision = "0005_drop_category_sort_order"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "categories",
        sa.Column("aliases_text", sa.Text(), nullable=False, server_default=""),
    )


def downgrade() -> None:
    op.drop_column("categories", "aliases_text")
