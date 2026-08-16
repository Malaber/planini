"""merge published list history and current main paths

Revision ID: 0022_add_list_history
Revises: 0021_add_list_history, 0021_merge_member_public_heads
Create Date: 2026-08-13
"""

revision = "0022_add_list_history"
down_revision = (
    "0021_add_list_history",
    "0021_merge_member_public_heads",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
