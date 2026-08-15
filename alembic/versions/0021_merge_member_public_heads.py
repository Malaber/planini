"""merge household member role and public list migration paths

Revision ID: 0021_merge_member_public_heads
Revises: 0020_add_household_member_roles, 0020_merge_public_sale_heads
Create Date: 2026-08-15
"""

revision = "0021_merge_member_public_heads"
down_revision = (
    "0020_add_household_member_roles",
    "0020_merge_public_sale_heads",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
