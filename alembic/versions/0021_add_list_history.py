"""add per-list history

Revision ID: 0021_add_list_history
Revises: 0020_add_household_member_roles, 0020_merge_public_sale_heads
Create Date: 2026-08-13
"""

from alembic import op
import sqlalchemy as sa

revision = "0021_add_list_history"
down_revision = (
    "0020_add_household_member_roles",
    "0020_merge_public_sale_heads",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "list_history_entries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("list_id", sa.Uuid(), nullable=True),
        sa.Column("actor_user_id", sa.Uuid(), nullable=False),
        sa.Column("actor_display_name", sa.String(length=120), nullable=False),
        sa.Column("event_type", sa.String(length=50), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=True),
        sa.Column("subject_name", sa.String(length=255), nullable=True),
        sa.Column("details", sa.JSON(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["household_id"], ["households.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_list_history_entries_household_created",
        "list_history_entries",
        ["household_id", "created_at"],
    )
    op.create_index(
        "ix_list_history_entries_list_created",
        "list_history_entries",
        ["list_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_list_history_entries_list_created", table_name="list_history_entries")
    op.drop_index(
        "ix_list_history_entries_household_created",
        table_name="list_history_entries",
    )
    op.drop_table("list_history_entries")
