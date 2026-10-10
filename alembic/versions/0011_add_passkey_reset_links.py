"""add passkey reset links

Revision ID: 0011_add_passkey_reset_links
Revises: 0010_add_auth_sessions
Create Date: 2026-04-04
"""

from alembic import op
import sqlalchemy as sa

revision = "0011_add_passkey_reset_links"
down_revision = "0010_add_auth_sessions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users", sa.Column("passkey_reset_token_hash", sa.String(length=64), nullable=True)
    )
    op.add_column(
        "users", sa.Column("passkey_reset_expires_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("users", "passkey_reset_expires_at")
    op.drop_column("users", "passkey_reset_token_hash")
