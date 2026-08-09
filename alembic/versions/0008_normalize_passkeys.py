"""normalize passkeys

Revision ID: 0008_normalize_passkeys
Revises: 0007_add_household_invites
Create Date: 2026-03-24
"""

import uuid

from alembic import op
import sqlalchemy as sa
from sqlalchemy.sql import text

revision = "0008_normalize_passkeys"
down_revision = "0007_add_household_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "passkeys",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("credential_id", sa.String(length=255), nullable=False),
        sa.Column("public_key", sa.LargeBinary(), nullable=False),
        sa.Column("sign_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("credential_id"),
    )

    bind = op.get_bind()
    users = sa.table(
        "users",
        sa.column("id", sa.Uuid()),
        sa.column("passkey_credential_id", sa.String(length=255)),
        sa.column("passkey_public_key", sa.LargeBinary()),
        sa.column("passkey_sign_count", sa.Integer()),
        sa.column("created_at", sa.DateTime(timezone=True)),
    )
    passkeys = sa.table(
        "passkeys",
        sa.column("id", sa.Uuid()),
        sa.column("user_id", sa.Uuid()),
        sa.column("credential_id", sa.String(length=255)),
        sa.column("public_key", sa.LargeBinary()),
        sa.column("sign_count", sa.Integer()),
        sa.column("created_at", sa.DateTime(timezone=True)),
    )
    existing_rows = bind.execute(
        sa.select(
            users.c.id,
            users.c.passkey_credential_id,
            users.c.passkey_public_key,
            users.c.passkey_sign_count,
            users.c.created_at,
        ).where(
            users.c.passkey_credential_id.is_not(None),
            users.c.passkey_public_key.is_not(None),
        )
    ).mappings()
    for row in existing_rows:
        bind.execute(
            sa.insert(passkeys).values(
                id=uuid.uuid4(),
                user_id=row["id"],
                credential_id=row["passkey_credential_id"],
                public_key=row["passkey_public_key"],
                sign_count=row["passkey_sign_count"] or 0,
                created_at=row["created_at"],
            )
        )

    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_constraint("uq_users_passkey_credential_id", type_="unique")
        batch_op.drop_column("passkey_sign_count")
        batch_op.drop_column("passkey_public_key")
        batch_op.drop_column("passkey_credential_id")


def downgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(
            sa.Column("passkey_credential_id", sa.String(length=255), nullable=True),
        )
        batch_op.add_column(sa.Column("passkey_public_key", sa.LargeBinary(), nullable=True))
        batch_op.add_column(
            sa.Column("passkey_sign_count", sa.Integer(), nullable=False, server_default="0")
        )
        batch_op.create_unique_constraint(
            "uq_users_passkey_credential_id", ["passkey_credential_id"]
        )

    bind = op.get_bind()
    bind.execute(text("""
            UPDATE users
            SET
                passkey_credential_id = (
                    SELECT credential_id
                    FROM passkeys
                    WHERE passkeys.user_id = users.id
                    ORDER BY created_at ASC, id ASC
                    LIMIT 1
                ),
                passkey_public_key = (
                    SELECT public_key
                    FROM passkeys
                    WHERE passkeys.user_id = users.id
                    ORDER BY created_at ASC, id ASC
                    LIMIT 1
                ),
                passkey_sign_count = COALESCE((
                    SELECT sign_count
                    FROM passkeys
                    WHERE passkeys.user_id = users.id
                    ORDER BY created_at ASC, id ASC
                    LIMIT 1
                ), 0)
            """))
    op.drop_table("passkeys")
