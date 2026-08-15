"""merge public-list and category-translation migration paths

Revision ID: 0019_add_public_list_links
Revises: 0018_add_public_list_links, 0018_add_category_translations
Create Date: 2026-06-27 00:00:00.000000
"""

revision: str = "0019_add_public_list_links"
down_revision = (
    "0018_add_public_list_links",
    "0018_add_category_translations",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
