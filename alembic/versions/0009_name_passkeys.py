"""name passkeys

Revision ID: 0009_name_passkeys
Revises: 0008_normalize_passkeys
Create Date: 2026-03-25
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.sql import text

revision = "0009_name_passkeys"
down_revision = "0008_normalize_passkeys"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("passkeys") as batch_op:
        batch_op.add_column(
            sa.Column("name", sa.String(length=120), nullable=False, server_default="Passkey")
        )

    bind = op.get_bind()
    user_ids = [row[0] for row in bind.execute(text("SELECT id FROM users ORDER BY id"))]
    for user_id in user_ids:
        passkeys = bind.execute(
            text("""
                SELECT id
                FROM passkeys
                WHERE user_id = :user_id
                ORDER BY created_at ASC, id ASC
                """),
            {"user_id": user_id},
        ).fetchall()
        for index, (passkey_id,) in enumerate(passkeys, start=1):
            bind.execute(
                text("UPDATE passkeys SET name = :name WHERE id = :id"),
                {"id": passkey_id, "name": f"Passkey {index}"},
            )

    with op.batch_alter_table("passkeys") as batch_op:
        batch_op.alter_column("name", server_default=None)


def downgrade() -> None:
    with op.batch_alter_table("passkeys") as batch_op:
        batch_op.drop_column("name")
