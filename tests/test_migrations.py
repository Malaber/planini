from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect, text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CURRENT_HEAD = "0021_merge_member_public_heads"


def _migration_config(database_path: Path) -> Config:
    config = Config(str(PROJECT_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(PROJECT_ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{database_path}")
    return config


def test_sale_migration_keeps_single_head_with_legacy_revisions(tmp_path: Path) -> None:
    config = _migration_config(tmp_path / "graph.db")
    scripts = ScriptDirectory.from_config(config)

    assert scripts.get_heads() == [CURRENT_HEAD]
    assert scripts.get_revision("0017_add_item_sale_window") is not None
    assert scripts.get_revision("0018_add_public_list_links") is not None
    assert scripts.get_revision("0019_add_public_list_links") is not None
    assert scripts.get_revision("0019_add_household_member_roles") is not None


def test_legacy_sale_database_upgrades_to_current_head(tmp_path: Path) -> None:
    database_path = tmp_path / "legacy-sale.db"
    config = _migration_config(database_path)
    command.upgrade(config, "0016_add_multi_use_invites")

    engine = create_engine(f"sqlite:///{database_path}")
    with engine.begin() as connection:
        connection.exec_driver_sql("ALTER TABLE grocery_items ADD COLUMN sale_starts_at DATETIME")
        connection.exec_driver_sql("ALTER TABLE grocery_items ADD COLUMN sale_ends_at DATETIME")

    command.stamp(config, "0017_add_item_sale_window", purge=True)
    command.upgrade(config, "head")

    item_columns = {column["name"] for column in inspect(engine).get_columns("grocery_items")}
    list_columns = {column["name"] for column in inspect(engine).get_columns("grocery_lists")}
    category_columns = {column["name"] for column in inspect(engine).get_columns("categories")}
    invite_columns = {column["name"] for column in inspect(engine).get_columns("household_invites")}
    table_names = inspect(engine).get_table_names()
    with engine.connect() as connection:
        current_revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    engine.dispose()

    assert {"sale_starts_at", "sale_ends_at"} <= item_columns
    assert "accent_color" in list_columns
    assert "translations_text" in category_columns
    assert "role" in invite_columns
    assert "public_list_links" in table_names
    assert current_revision == CURRENT_HEAD


def test_deployed_member_role_database_upgrades_to_current_head(tmp_path: Path) -> None:
    database_path = tmp_path / "deployed-member-role.db"
    config = _migration_config(database_path)
    command.upgrade(config, "0019_add_household_member_roles")

    engine = create_engine(f"sqlite:///{database_path}")
    assert "role" in {column["name"] for column in inspect(engine).get_columns("household_invites")}
    assert "sale_starts_at" not in {
        column["name"] for column in inspect(engine).get_columns("grocery_items")
    }
    assert "public_list_links" not in inspect(engine).get_table_names()

    command.upgrade(config, "head")

    item_columns = {column["name"] for column in inspect(engine).get_columns("grocery_items")}
    table_names = inspect(engine).get_table_names()
    with engine.connect() as connection:
        current_revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    engine.dispose()

    assert {"sale_starts_at", "sale_ends_at"} <= item_columns
    assert "public_list_links" in table_names
    assert current_revision == CURRENT_HEAD


def test_current_sale_database_applies_sibling_migrations(tmp_path: Path) -> None:
    database_path = tmp_path / "current-sale.db"
    config = _migration_config(database_path)
    command.upgrade(config, "0018_add_item_sale_window")

    engine = create_engine(f"sqlite:///{database_path}")
    assert "translations_text" not in {
        column["name"] for column in inspect(engine).get_columns("categories")
    }

    command.upgrade(config, "head")

    category_columns = {column["name"] for column in inspect(engine).get_columns("categories")}
    invite_columns = {column["name"] for column in inspect(engine).get_columns("household_invites")}
    table_names = inspect(engine).get_table_names()
    with engine.connect() as connection:
        current_revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    engine.dispose()

    assert "translations_text" in category_columns
    assert "role" in invite_columns
    assert "public_list_links" in table_names
    assert current_revision == CURRENT_HEAD


def test_public_list_database_upgrades_to_sale_and_merged_head(tmp_path: Path) -> None:
    database_path = tmp_path / "public-list.db"
    config = _migration_config(database_path)
    command.upgrade(config, "0019_add_public_list_links")

    engine = create_engine(f"sqlite:///{database_path}")
    assert "public_list_links" in inspect(engine).get_table_names()
    assert "sale_starts_at" not in {
        column["name"] for column in inspect(engine).get_columns("grocery_items")
    }

    command.upgrade(config, "head")

    item_columns = {column["name"] for column in inspect(engine).get_columns("grocery_items")}
    invite_columns = {column["name"] for column in inspect(engine).get_columns("household_invites")}
    with engine.connect() as connection:
        current_revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    engine.dispose()

    assert {"sale_starts_at", "sale_ends_at"} <= item_columns
    assert "role" in invite_columns
    assert current_revision == CURRENT_HEAD


def test_deployed_public_list_database_upgrades_to_current_head(tmp_path: Path) -> None:
    database_path = tmp_path / "deployed-public-list.db"
    config = _migration_config(database_path)
    command.upgrade(config, "0018_add_public_list_links")

    engine = create_engine(f"sqlite:///{database_path}")
    assert "public_list_links" in inspect(engine).get_table_names()
    assert "translations_text" not in {
        column["name"] for column in inspect(engine).get_columns("categories")
    }

    command.upgrade(config, "head")

    category_columns = {column["name"] for column in inspect(engine).get_columns("categories")}
    item_columns = {column["name"] for column in inspect(engine).get_columns("grocery_items")}
    invite_columns = {column["name"] for column in inspect(engine).get_columns("household_invites")}
    with engine.connect() as connection:
        current_revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    engine.dispose()

    assert "translations_text" in category_columns
    assert {"sale_starts_at", "sale_ends_at"} <= item_columns
    assert "role" in invite_columns
    assert current_revision == CURRENT_HEAD
