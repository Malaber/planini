"""merge household member role and sale migration paths

Revision ID: 0020_add_household_member_roles
Revises: 0019_add_household_member_roles, 0019_merge_sale_revision_heads
Create Date: 2026-07-24
"""

revision = "0020_add_household_member_roles"
down_revision = (
    "0019_add_household_member_roles",
    "0019_merge_sale_revision_heads",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
