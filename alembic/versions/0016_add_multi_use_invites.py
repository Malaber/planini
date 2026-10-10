"""add multi-use household invites

Revision ID: 0016_add_multi_use_invites
Revises: 0015_add_passkey_add_links
Create Date: 2026-06-27
"""

from alembic import op
import sqlalchemy as sa

revision = "0016_add_multi_use_invites"
down_revision = "0015_add_passkey_add_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("household_invites", sa.Column("max_uses", sa.Integer(), nullable=True))
    with op.batch_alter_table("household_invites") as batch_op:
        batch_op.alter_column("expires_at", existing_type=sa.DateTime(timezone=True), nullable=True)
    op.create_table(
        "household_invite_uses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("invite_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("slot_number", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["invite_id"], ["household_invites.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("invite_id", "slot_number", name="uq_household_invite_use_slot"),
        sa.UniqueConstraint("invite_id", "user_id", name="uq_household_invite_use_user"),
    )


def downgrade() -> None:
    op.drop_table("household_invite_uses")
    with op.batch_alter_table("household_invites") as batch_op:
        batch_op.alter_column(
            "expires_at", existing_type=sa.DateTime(timezone=True), nullable=False
        )
    op.drop_column("household_invites", "max_uses")
