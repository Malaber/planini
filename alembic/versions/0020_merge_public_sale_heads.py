"""merge public list and sale migration paths

Revision ID: 0020_merge_public_sale_heads
Revises: 0019_add_public_list_links, 0019_merge_sale_revision_heads
Create Date: 2026-08-11
"""

revision = "0020_merge_public_sale_heads"
down_revision = (
    "0019_add_public_list_links",
    "0019_merge_sale_revision_heads",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
