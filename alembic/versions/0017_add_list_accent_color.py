"""add optional list accent color

Revision ID: 0017_add_list_accent_color
Revises: 0016_add_multi_use_invites
Create Date: 2026-07-23
"""

from alembic import op
import sqlalchemy as sa

revision = "0017_add_list_accent_color"
down_revision = "0016_add_multi_use_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "grocery_lists",
        sa.Column("accent_color", sa.String(length=7), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("grocery_lists", "accent_color")
