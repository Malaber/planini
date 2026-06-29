import asyncio
import base64
import json

import pytest
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.main import app
from app.models import (
    Category,
    GroceryItem,
    GroceryList,
    Household,
    HouseholdMember,
    ListCategoryOrder,
    Passkey,
    User,
)
from app.services.fixture_seed import ensure_seed_data
from db_utils import dispose_db, reset_db


def _fixture_payload() -> dict[str, object]:
    return {
        "users": [
            {
                "email": "owner@example.com",
                "display_name": "Owner",
                "is_admin": True,
                "passkey": {
                    "credential_id": "owner-credential-id",
                    "public_key_b64": base64.b64encode(b"owner-public-key").decode("ascii"),
                    "sign_count": 7,
                },
            },
            {
                "email": "member@example.com",
                "display_name": "Member",
                "is_admin": False,
                "passkey": {
                    "credential_id": "member-credential-id",
                    "public_key_b64": base64.b64encode(b"member-public-key").decode("ascii"),
                    "sign_count": 3,
                },
            },
        ],
        "categories": [
            {"name": "Produce", "color": "green", "aliases": ["Veg"]},
            {"name": "Frozen", "color": "blue", "aliases": ["Ice"]},
            {"name": "Cleaning", "color": "purple", "household": "Cabin"},
        ],
        "households": [
            {
                "name": "Home",
                "owner_email": "owner@example.com",
                "members": [
                    {"email": "owner@example.com", "role": "owner"},
                    {"email": "member@example.com", "role": "member"},
                ],
                "lists": [
                    {
                        "name": "Weekly shop",
                        "created_by_email": "owner@example.com",
                        "category_order": ["Produce", "Frozen"],
                        "items": [
                            {
                                "name": "Apples",
                                "category": "Produce",
                                "quantity_text": "6",
                                "created_by_email": "owner@example.com",
                            },
                            {
                                "name": "Peas",
                                "category": "Frozen",
                                "checked": True,
                                "checked_by_email": "member@example.com",
                                "created_by_email": "owner@example.com",
                                "updated_by_email": "member@example.com",
                            },
                        ],
                    }
                ],
            },
            {
                "name": "Cabin",
                "owner_email": "member@example.com",
                "members": [{"email": "member@example.com", "role": "owner"}],
                "lists": [
                    {
                        "name": "Weekend",
                        "created_by_email": "member@example.com",
                        "category_order": ["Cleaning"],
                        "items": [
                            {
                                "name": "Soap",
                                "category": "Cleaning",
                                "note": "For guests",
                                "created_by_email": "member@example.com",
                            }
                        ],
                    }
                ],
            },
        ],
    }


def test_seed_data_populates_real_database_and_passkeys(tmp_path) -> None:
    fixture_path = tmp_path / "seed.json"
    fixture_path.write_text(json.dumps(_fixture_payload()), encoding="utf-8")
    asyncio.run(reset_db())

    async def _assert_seeded() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(fixture_path))
            await ensure_seed_data(session, str(fixture_path))

            users = (await session.execute(select(User).order_by(User.email.asc()))).scalars().all()
            assert [user.email for user in users] == ["member@example.com", "owner@example.com"]
            owner_passkeys = (
                (await session.execute(select(Passkey).where(Passkey.user_id == users[1].id)))
                .scalars()
                .all()
            )
            assert len(owner_passkeys) == 1
            assert owner_passkeys[0].name == "Passkey 1"
            assert owner_passkeys[0].credential_id == "owner-credential-id"
            assert owner_passkeys[0].public_key == b"owner-public-key"
            assert owner_passkeys[0].sign_count == 7

            households = (
                (await session.execute(select(Household).order_by(Household.name.asc())))
                .scalars()
                .all()
            )
            assert [household.name for household in households] == ["Cabin", "Home"]

            memberships = (
                (
                    await session.execute(
                        select(HouseholdMember).order_by(HouseholdMember.role.asc())
                    )
                )
                .scalars()
                .all()
            )
            assert len(memberships) == 3

            categories = (
                (await session.execute(select(Category).order_by(Category.name.asc())))
                .scalars()
                .all()
            )
            assert [category.name for category in categories] == ["Cleaning", "Frozen", "Produce"]

            grocery_lists = (
                (await session.execute(select(GroceryList).order_by(GroceryList.name.asc())))
                .scalars()
                .all()
            )
            assert [grocery_list.name for grocery_list in grocery_lists] == [
                "Weekend",
                "Weekly shop",
            ]

            items = (
                (await session.execute(select(GroceryItem).order_by(GroceryItem.name.asc())))
                .scalars()
                .all()
            )
            assert [item.name for item in items] == ["Apples", "Peas", "Soap"]
            checked_item = next(item for item in items if item.name == "Peas")
            assert checked_item.checked is True
            assert checked_item.checked_by is not None

    try:
        asyncio.run(_assert_seeded())
    finally:
        asyncio.run(dispose_db())


def test_lifespan_runs_seed_data_fixture(monkeypatch, tmp_path) -> None:
    fixture_path = tmp_path / "seed.json"
    fixture_path.write_text(json.dumps(_fixture_payload()), encoding="utf-8")
    monkeypatch.setattr("app.main.settings.seed_data_path", str(fixture_path))
    asyncio.run(reset_db())

    try:
        from fastapi.testclient import TestClient

        with TestClient(app):
            pass

        async def _assert_seeded() -> None:
            async with AsyncSessionLocal() as session:
                users = (await session.execute(select(User))).scalars().all()
                assert len(users) == 2

        asyncio.run(_assert_seeded())
    finally:
        monkeypatch.setattr("app.main.settings.seed_data_path", None)
        asyncio.run(dispose_db())


def test_lifespan_logs_and_reraises_startup_failures(monkeypatch) -> None:
    async def _failing_run_migrations() -> None:
        raise RuntimeError("boom")

    monkeypatch.setattr("app.main.run_migrations", _failing_run_migrations)
    monkeypatch.setattr("app.main.settings.seed_data_path", None)

    from fastapi.testclient import TestClient

    with pytest.raises(RuntimeError, match="boom"):
        with TestClient(app):
            pass


def test_lifespan_refuses_missing_privacy_email(monkeypatch) -> None:
    monkeypatch.setattr("app.main.settings.privacy_email", None)

    from fastapi.testclient import TestClient

    with pytest.raises(RuntimeError, match="PRIVACY_EMAIL must be set"):
        with TestClient(app):
            pass


def test_lifespan_refuses_missing_support_email(monkeypatch) -> None:
    monkeypatch.setattr("app.main.settings.support_email", None)

    from fastapi.testclient import TestClient

    with pytest.raises(RuntimeError, match="SUPPORT_EMAIL must be set"):
        with TestClient(app):
            pass


def test_seed_data_enforces_preview_member_and_admin_membership_rules(tmp_path) -> None:
    fixture_path = tmp_path / "seed-preview-users.json"
    fixture_path.write_text(
        json.dumps(
            {
                "users": [
                    {
                        "email": "planini_admin@schaedler.rocks",
                        "display_name": "Admin",
                        "is_admin": True,
                    },
                    {
                        "email": "planini@schaedler.rocks",
                        "display_name": "Member",
                        "is_admin": False,
                    },
                    {"email": "other@example.com", "display_name": "Other", "is_admin": False},
                ],
                "households": [
                    {
                        "name": "Home",
                        "owner_email": "planini@schaedler.rocks",
                        "members": [{"email": "planini_admin@schaedler.rocks", "role": "member"}],
                        "lists": [],
                    },
                    {
                        "name": "Cabin",
                        "owner_email": "other@example.com",
                        "members": [],
                        "lists": [],
                    },
                ],
            }
        ),
        encoding="utf-8",
    )
    asyncio.run(reset_db())

    async def _assert_rules() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(fixture_path))
            users = (await session.execute(select(User))).scalars().all()
            by_email = {user.email: user for user in users}
            admin_user = by_email["planini_admin@schaedler.rocks"]
            member_user = by_email["planini@schaedler.rocks"]
            households = (await session.execute(select(Household))).scalars().all()
            assert len(households) == 2
            for household in households:
                member_link = await session.execute(
                    select(HouseholdMember).where(
                        HouseholdMember.household_id == household.id,
                        HouseholdMember.user_id == member_user.id,
                    )
                )
                assert member_link.scalar_one_or_none() is not None
                admin_link = await session.execute(
                    select(HouseholdMember).where(
                        HouseholdMember.household_id == household.id,
                        HouseholdMember.user_id == admin_user.id,
                    )
                )
                assert admin_link.scalar_one_or_none() is None

    try:
        asyncio.run(_assert_rules())
    finally:
        asyncio.run(dispose_db())


def test_seed_data_updates_existing_rows_and_removes_stale_items(tmp_path) -> None:
    initial_fixture_path = tmp_path / "seed-initial.json"
    updated_fixture_path = tmp_path / "seed-updated.json"

    initial_payload = _fixture_payload()
    updated_payload = {
        "users": [
            {
                "email": "owner@example.com",
                "display_name": "Owner Updated",
                "is_admin": False,
            },
            {
                "email": "member@example.com",
                "display_name": "Member Updated",
                "is_admin": True,
                "is_active": False,
                "passkey": {
                    "credential_id": "member-credential-id-updated",
                    "public_key_b64": base64.b64encode(b"member-updated-public-key").decode(
                        "ascii"
                    ),
                },
            },
        ],
        "categories": [
            {"name": "Produce", "color": "red", "aliases": ["Fresh"]},
            {"name": "Cleaning", "color": None, "aliases": [], "household": "Cabin"},
        ],
        "households": [
            {
                "name": "Home",
                "owner_email": "owner@example.com",
                "members": [{"email": "member@example.com", "role": "editor"}],
                "lists": [
                    {
                        "name": "Weekly shop",
                        "created_by_email": "member@example.com",
                        "category_order": ["Produce"],
                        "items": [
                            {
                                "name": "Peas",
                                "category": "Produce",
                                "quantity_text": "2 bags",
                                "note": "Keep frozen",
                                "created_by_email": "owner@example.com",
                                "updated_by_email": "member@example.com",
                            },
                            {
                                "name": "Bread",
                                "created_by_email": "member@example.com",
                                "checked": True,
                            },
                        ],
                    }
                ],
            },
            {
                "name": "Home",
                "owner_email": "owner@example.com",
                "members": [],
                "lists": [],
            },
            {
                "name": "Cabin",
                "owner_email": "member@example.com",
                "members": [{"email": "member@example.com", "role": "owner"}],
                "lists": [
                    {
                        "name": "Weekend",
                        "created_by_email": "member@example.com",
                        "category_order": ["Cleaning"],
                        "items": [],
                    }
                ],
            },
        ],
    }

    initial_fixture_path.write_text(json.dumps(initial_payload), encoding="utf-8")
    updated_fixture_path.write_text(json.dumps(updated_payload), encoding="utf-8")
    asyncio.run(reset_db())

    async def _assert_updated() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(initial_fixture_path))
            await ensure_seed_data(session, str(updated_fixture_path))

            users = {
                user.email: user for user in (await session.execute(select(User))).scalars().all()
            }
            assert users["owner@example.com"].display_name == "Owner Updated"
            assert users["owner@example.com"].is_admin is False
            assert users["member@example.com"].display_name == "Member Updated"
            assert users["member@example.com"].is_admin is True
            assert users["member@example.com"].is_active is False
            member_passkeys = (
                (
                    await session.execute(
                        select(Passkey).where(Passkey.user_id == users["member@example.com"].id)
                    )
                )
                .scalars()
                .all()
            )
            assert len(member_passkeys) == 1
            assert member_passkeys[0].name == "Passkey 1"
            assert member_passkeys[0].credential_id == "member-credential-id-updated"
            assert member_passkeys[0].public_key == b"member-updated-public-key"
            assert member_passkeys[0].sign_count == 0

            home = (
                await session.execute(select(Household).where(Household.name == "Home"))
            ).scalar_one()
            assert home.owner_user_id == users["owner@example.com"].id

            members = (
                (
                    await session.execute(
                        select(HouseholdMember).where(HouseholdMember.household_id == home.id)
                    )
                )
                .scalars()
                .all()
            )
            member_roles = {member.user_id: member.role for member in members}
            assert member_roles[users["owner@example.com"].id] == "owner"
            assert member_roles[users["member@example.com"].id] == "editor"

            produce = (
                await session.execute(
                    select(Category).where(
                        Category.household_id.is_(None), Category.name == "Produce"
                    )
                )
            ).scalar_one()
            assert produce.color == "red"
            assert produce.aliases == ["Fresh"]

            weekly_list = (
                await session.execute(select(GroceryList).where(GroceryList.name == "Weekly shop"))
            ).scalar_one()
            items = (
                (
                    await session.execute(
                        select(GroceryItem)
                        .where(GroceryItem.list_id == weekly_list.id)
                        .order_by(GroceryItem.name.asc())
                    )
                )
                .scalars()
                .all()
            )
            assert [item.name for item in items] == ["Bread", "Peas"]

            peas = next(item for item in items if item.name == "Peas")
            assert peas.quantity_text == "2 bags"
            assert peas.note == "Keep frozen"
            assert peas.checked is False
            assert peas.checked_by is None
            assert peas.checked_at is None
            assert peas.category_id == produce.id

            bread = next(item for item in items if item.name == "Bread")
            assert bread.category_id is None
            assert bread.checked is True
            assert bread.checked_by == users["member@example.com"].id
            assert bread.checked_at is not None

            category_order = (
                (
                    await session.execute(
                        select(ListCategoryOrder)
                        .where(ListCategoryOrder.list_id == weekly_list.id)
                        .order_by(ListCategoryOrder.sort_order.asc())
                    )
                )
                .scalars()
                .all()
            )
            assert [entry.category_id for entry in category_order] == [produce.id]

    try:
        asyncio.run(_assert_updated())
    finally:
        asyncio.run(dispose_db())


def test_seed_data_supports_multiple_passkeys_array(tmp_path) -> None:
    fixture_path = tmp_path / "seed-multi-passkeys.json"
    fixture_path.write_text(
        json.dumps(
            {
                "users": [
                    {
                        "email": "owner@example.com",
                        "display_name": "Owner",
                        "passkeys": [
                            {
                                "name": "Owner laptop",
                                "credential_id": "owner-passkey-1",
                                "public_key_b64": base64.b64encode(b"owner-key-1").decode("ascii"),
                                "sign_count": 2,
                            },
                            {
                                "credential_id": "owner-passkey-2",
                                "public_key_b64": base64.b64encode(b"owner-key-2").decode("ascii"),
                                "sign_count": 5,
                            },
                        ],
                    }
                ],
                "households": [],
                "categories": [],
            }
        ),
        encoding="utf-8",
    )
    asyncio.run(reset_db())

    async def _assert_seeded() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(fixture_path))
            user = (
                await session.execute(select(User).where(User.email == "owner@example.com"))
            ).scalar_one()
            passkeys = (
                (
                    await session.execute(
                        select(Passkey)
                        .where(Passkey.user_id == user.id)
                        .order_by(Passkey.credential_id.asc())
                    )
                )
                .scalars()
                .all()
            )
            assert [passkey.credential_id for passkey in passkeys] == [
                "owner-passkey-1",
                "owner-passkey-2",
            ]
            assert [passkey.name for passkey in passkeys] == ["Owner laptop", "Passkey 2"]

    try:
        asyncio.run(_assert_seeded())
    finally:
        asyncio.run(dispose_db())


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        (["not-a-dict"], "Seed fixture must be a JSON object"),
        ({"users": {}}, "Seed fixture users must be a list"),
        ({"users": [], "households": {}}, "Seed fixture households must be a list"),
        (
            {"users": [], "households": [], "categories": {}},
            "Seed fixture categories must be a list",
        ),
        (
            {
                "users": [
                    {
                        "email": "owner@example.com",
                        "display_name": "Owner",
                        "passkey": "invalid",
                    }
                ]
            },
            "Passkey fixture for owner@example.com must be an object",
        ),
        (
            {
                "users": [
                    {
                        "email": "owner@example.com",
                        "display_name": "Owner",
                        "passkeys": {},
                    }
                ]
            },
            "Passkeys fixture for owner@example.com must be a list",
        ),
        (
            {
                "users": [
                    {
                        "email": "owner@example.com",
                        "display_name": "Owner",
                        "passkeys": ["invalid"],
                    }
                ]
            },
            "Each passkey fixture for owner@example.com must be an object",
        ),
        (
            {
                "users": [{"email": "owner@example.com", "display_name": "Owner"}],
                "households": [{"name": "Home", "owner_email": "owner@example.com", "members": {}}],
            },
            "Household members for Home must be a list",
        ),
        (
            {
                "users": [{"email": "owner@example.com", "display_name": "Owner"}],
                "households": [
                    {
                        "name": "Home",
                        "owner_email": "owner@example.com",
                        "members": [],
                        "lists": {},
                    }
                ],
            },
            "Household lists for Home must be a list",
        ),
        (
            {
                "users": [{"email": "owner@example.com", "display_name": "Owner"}],
                "categories": [{"name": "Produce"}],
                "households": [
                    {
                        "name": "Home",
                        "owner_email": "owner@example.com",
                        "members": [],
                        "lists": [
                            {
                                "name": "Weekly shop",
                                "created_by_email": "owner@example.com",
                                "category_order": ["Missing"],
                                "items": [],
                            }
                        ],
                    }
                ],
            },
            "Unknown category Missing for list Weekly shop",
        ),
    ],
)
def test_seed_data_validates_fixture_shapes(tmp_path, payload, message) -> None:
    fixture_path = tmp_path / "invalid-seed.json"
    fixture_path.write_text(json.dumps(payload), encoding="utf-8")
    asyncio.run(reset_db())

    async def _run() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(fixture_path))

    try:
        with pytest.raises(ValueError, match=message):
            asyncio.run(_run())
    finally:
        asyncio.run(dispose_db())
