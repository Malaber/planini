"""preserve legacy item sale window revision

Revision ID: 0017_add_item_sale_window
Revises: 0016_add_multi_use_invites
Create Date: 2026-07-23

This revision shipped in early PLAN-134 review images. Its schema changes now
live in 0018_add_item_sale_window, which safely handles databases stamped with
either revision path.
"""

revision = "0017_add_item_sale_window"
down_revision = "0016_add_multi_use_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
