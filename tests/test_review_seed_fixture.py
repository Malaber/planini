import asyncio
import json
from pathlib import Path

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models import Passkey, User
from app.services.fixture_seed import ensure_seed_data
from db_utils import dispose_db, reset_db


def test_review_seed_fixture_has_unique_passkey_credentials_and_seeds() -> None:
    fixture_path = Path("app/fixtures/review_seed.json")
    payload = json.loads(fixture_path.read_text(encoding="utf-8"))
    users = payload["users"]
    emails = {user["email"] for user in users}

    credential_ids = [
        user["passkey"]["credential_id"] for user in users if isinstance(user.get("passkey"), dict)
    ]
    assert len(credential_ids) == len(set(credential_ids))
    assert "planini_admin@schaedler.rocks" in emails
    assert "planini@schaedler.rocks" in emails
    for user in users:
        passkey = user.get("passkey")
        if isinstance(passkey, dict):
            assert "private_key_pkcs8_b64" not in passkey
            assert "user_handle_b64" not in passkey

    asyncio.run(reset_db())

    async def _assert_seeded() -> None:
        async with AsyncSessionLocal() as session:
            await ensure_seed_data(session, str(fixture_path))

            seeded_users = (
                (
                    await session.execute(
                        select(User).where(
                            User.email.in_(
                                [
                                    "planini_admin@schaedler.rocks",
                                    "planini@schaedler.rocks",
                                    "preview@example.com",
                                    "preview-invitee@example.com",
                                ]
                            )
                        )
                    )
                )
                .scalars()
                .all()
            )
            assert len(seeded_users) == 4

            passkeys = (
                (await session.execute(select(Passkey).order_by(Passkey.credential_id.asc())))
                .scalars()
                .all()
            )
            assert len(passkeys) >= 3

    try:
        asyncio.run(_assert_seeded())
    finally:
        asyncio.run(dispose_db())


def test_review_e2e_seed_fixture_contains_private_passkey_material() -> None:
    fixture_path = Path("app/fixtures/review_seed_e2e.json")
    payload = json.loads(fixture_path.read_text(encoding="utf-8"))
    users = {user["email"]: user for user in payload["users"]}
    primary_household = next(
        household
        for household in payload["households"]
        if household["name"] == payload["e2e"]["primary_household"]
    )
    checked_stress_list = next(
        grocery_list
        for grocery_list in primary_household["lists"]
        if grocery_list["name"] == payload["e2e"]["checked_stress_list"]
    )

    assert payload["e2e"]["owner_email"] == "planini@schaedler.rocks"
    assert payload["e2e"]["invitee_email"] == "preview-invitee@example.com"
    assert payload["e2e"]["checked_stress_list"] == "Checked History Stress Test"
    assert sum(1 for item in checked_stress_list["items"] if item["checked"]) == 258
    assert users["planini@schaedler.rocks"]["passkey"]["private_key_pkcs8_b64"]
    assert users["planini@schaedler.rocks"]["passkey"]["user_handle_b64"]
    assert users["preview-invitee@example.com"]["passkey"]["private_key_pkcs8_b64"]
    assert users["preview-invitee@example.com"]["passkey"]["user_handle_b64"]


def test_ios_marketing_seed_fixture_contains_only_polished_screenshot_data() -> None:
    fixture_path = Path("app/fixtures/ios_marketing_seed.json")
    payload = json.loads(fixture_path.read_text(encoding="utf-8"))
    households = payload["households"]
    grocery_lists = [
        grocery_list for household in households for grocery_list in household["lists"]
    ]
    visible_names = [
        payload["users"][0]["display_name"],
        *(household["name"] for household in households),
        *(grocery_list["name"] for grocery_list in grocery_lists),
        *(item["name"] for grocery_list in grocery_lists for item in grocery_list["items"]),
    ]

    assert payload["users"][0]["email"] == "planini@schaedler.rocks"
    assert [grocery_list["name"] for grocery_list in grocery_lists] == [
        "Weekly groceries",
        "Dinner with friends",
        "Weekend brunch",
    ]
    assert all("test" not in name.lower() for name in visible_names)
    assert all("updated" not in name.lower() for name in visible_names)
