"""add household member roles

Revision ID: 0019_add_household_member_roles
Revises: 0018_add_category_translations
Create Date: 2026-07-24
"""

from alembic import op
import sqlalchemy as sa

revision = "0019_add_household_member_roles"
down_revision = "0018_add_category_translations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("UPDATE household_members SET role = 'editor' WHERE role = 'member'")
    op.add_column(
        "household_invites",
        sa.Column("role", sa.String(length=20), nullable=False, server_default="editor"),
    )


def downgrade() -> None:
    op.drop_column("household_invites", "role")
    op.execute("UPDATE household_members SET role = 'member' WHERE role = 'editor'")
