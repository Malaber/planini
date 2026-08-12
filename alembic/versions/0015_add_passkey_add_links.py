"""add passkey add link records

Revision ID: 0015_add_passkey_add_links
Revises: 0014_merge_item_hidden_until_and_disabled_categories
Create Date: 2026-05-15
"""

from alembic import op
import sqlalchemy as sa

revision = "0015_add_passkey_add_links"
down_revision = "0014_merge_item_hidden_until_and_disabled_categories"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "passkey_add_links",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.drop_column("users", "passkey_reset_expires_at")
    op.drop_column("users", "passkey_reset_token_hash")


def downgrade() -> None:
    op.add_column(
        "users", sa.Column("passkey_reset_token_hash", sa.String(length=64), nullable=True)
    )
    op.add_column(
        "users", sa.Column("passkey_reset_expires_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.drop_table("passkey_add_links")
