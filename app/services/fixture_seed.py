import base64
import json
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

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

PREVIEW_INSTANCE_ADMIN_EMAIL = "planini_admin@schaedler.rocks"
PREVIEW_MEMBER_EMAIL = "planini@schaedler.rocks"


def _decode_public_key(value: str) -> bytes:
    return base64.b64decode(value.encode("ascii"))


def _load_fixture(path: str) -> dict[str, object]:
    with Path(path).open("r", encoding="utf-8") as handle:
        loaded = json.load(handle)
    if not isinstance(loaded, dict):
        raise ValueError("Seed fixture must be a JSON object")
    return loaded


def _passkey_payloads(payload: dict[str, object], email: str) -> list[dict[str, object]] | None:
    passkeys = payload.get("passkeys")
    if passkeys is not None:
        if not isinstance(passkeys, list):
            raise ValueError(f"Passkeys fixture for {email} must be a list")
        if not all(isinstance(entry, dict) for entry in passkeys):
            raise ValueError(f"Each passkey fixture for {email} must be an object")
        return list(passkeys)

    passkey = payload.get("passkey")
    if passkey is None:
        return None
    if not isinstance(passkey, dict):
        raise ValueError(f"Passkey fixture for {email} must be an object")
    return [passkey]


def _fixture_passkey_name(payload: dict[str, object], index: int) -> str:
    raw_name = payload.get("name")
    if isinstance(raw_name, str) and raw_name.strip():
        return raw_name.strip()
    return f"Passkey {index + 1}"


async def _ensure_user(db: AsyncSession, payload: dict[str, object]) -> User:
    email = str(payload["email"])
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    if user is None:
        user = User(
            email=email,
            password_hash="",
            display_name=str(payload["display_name"]),
        )
        db.add(user)
        await db.flush()

    user.display_name = str(payload["display_name"])
    user.is_admin = bool(payload.get("is_admin", False))
    user.is_active = bool(payload.get("is_active", True))

    passkeys = _passkey_payloads(payload, email)
    if passkeys is not None:
        existing_passkeys = (
            (await db.execute(select(Passkey).where(Passkey.user_id == user.id))).scalars().all()
        )
        by_credential_id = {passkey.credential_id: passkey for passkey in existing_passkeys}
        fixture_credential_ids = {str(passkey["credential_id"]) for passkey in passkeys}

        for existing_passkey in existing_passkeys:
            if existing_passkey.credential_id not in fixture_credential_ids:
                await db.delete(existing_passkey)

        for index, passkey_payload in enumerate(passkeys):
            credential_id = str(passkey_payload["credential_id"])
            passkey = by_credential_id.get(credential_id)
            if passkey is None:
                passkey = Passkey(
                    user_id=user.id,
                    name=_fixture_passkey_name(passkey_payload, index),
                    credential_id=credential_id,
                )
                db.add(passkey)

            passkey.name = _fixture_passkey_name(passkey_payload, index)
            passkey.public_key = _decode_public_key(str(passkey_payload["public_key_b64"]))
            passkey.sign_count = int(passkey_payload.get("sign_count", 0))

    return user


async def _resolve_users(
    db: AsyncSession, users_payload: list[dict[str, object]]
) -> dict[str, User]:
    users: dict[str, User] = {}
    for payload in users_payload:
        user = await _ensure_user(db, payload)
        users[user.email] = user
    return users


async def _ensure_household(
    db: AsyncSession,
    households: dict[str, Household],
    users: dict[str, User],
    payload: dict[str, object],
) -> Household:
    name = str(payload["name"])
    owner = users[str(payload["owner_email"])]
    household = households.get(name)
    if household is None:
        result = await db.execute(
            select(Household).where(Household.name == name, Household.owner_user_id == owner.id)
        )
        household = result.scalar_one_or_none()

    if household is None:
        household = Household(name=name, owner_user_id=owner.id)
        db.add(household)
        await db.flush()
    else:
        household.owner_user_id = owner.id

    households[name] = household
    return household


async def _ensure_member(
    db: AsyncSession, household: Household, user: User, role: str
) -> HouseholdMember:
    result = await db.execute(
        select(HouseholdMember).where(
            HouseholdMember.household_id == household.id,
            HouseholdMember.user_id == user.id,
        )
    )
    membership = result.scalar_one_or_none()
    if membership is None:
        membership = HouseholdMember(household_id=household.id, user_id=user.id, role=role)
        db.add(membership)
        await db.flush()
    else:
        membership.role = role
    return membership


async def _ensure_category(
    db: AsyncSession,
    household_by_name: dict[str, Household],
    payload: dict[str, object],
) -> Category:
    household_name = payload.get("household")
    household_id = None
    if household_name is not None:
        household_id = household_by_name[str(household_name)].id

    result = await db.execute(
        select(Category).where(
            Category.household_id == household_id, Category.name == str(payload["name"])
        )
    )
    category = result.scalar_one_or_none()
    if category is None:
        category = Category(
            household_id=household_id,
            name=str(payload["name"]),
            color=payload.get("color") and str(payload["color"]),
        )
        db.add(category)
    else:
        category.color = payload.get("color") and str(payload["color"])

    category.aliases = [str(alias) for alias in payload.get("aliases", [])]
    category.translations = {
        str(locale): str(value) for locale, value in dict(payload.get("translations", {})).items()
    }
    await db.flush()
    return category


async def _ensure_list(
    db: AsyncSession,
    household: Household,
    users: dict[str, User],
    payload: dict[str, object],
) -> GroceryList:
    name = str(payload["name"])
    created_by = users[str(payload["created_by_email"])]
    result = await db.execute(
        select(GroceryList).where(
            GroceryList.household_id == household.id, GroceryList.name == name
        )
    )
    grocery_list = result.scalar_one_or_none()
    if grocery_list is None:
        accent_color = payload.get("accent_color")
        grocery_list = GroceryList(
            household_id=household.id,
            name=name,
            accent_color=str(accent_color) if accent_color is not None else None,
            created_by=created_by.id,
        )
        db.add(grocery_list)
        await db.flush()
    else:
        grocery_list.created_by = created_by.id
        if "accent_color" in payload:
            accent_color = payload["accent_color"]
            grocery_list.accent_color = str(accent_color) if accent_color is not None else None
    return grocery_list


async def _seed_list_items(
    db: AsyncSession,
    grocery_list: GroceryList,
    users: dict[str, User],
    categories: dict[tuple[str | None, str], Category],
    household_name: str,
    payload: dict[str, object],
) -> None:
    existing_items_result = await db.execute(
        select(GroceryItem).where(GroceryItem.list_id == grocery_list.id)
    )
    existing_items = {item.name: item for item in existing_items_result.scalars().all()}
    fixture_item_names = {str(item_payload["name"]) for item_payload in payload.get("items", [])}
    for item_name, item in existing_items.items():
        if item_name not in fixture_item_names:
            await db.delete(item)
    await db.flush()

    for index, item_payload in enumerate(payload.get("items", [])):
        item_name = str(item_payload["name"])
        item = existing_items.get(item_name)
        created_by = users[str(item_payload["created_by_email"])]
        updated_by = users[
            str(item_payload.get("updated_by_email", item_payload["created_by_email"]))
        ]
        category_name = item_payload.get("category")
        category = None
        if category_name is not None:
            category = categories.get((household_name, str(category_name))) or categories.get(
                (None, str(category_name))
            )

        if item is None:
            item = GroceryItem(
                list_id=grocery_list.id,
                name=item_name,
                created_by=created_by.id,
            )
            db.add(item)

        item.quantity_text = item_payload.get("quantity_text") and str(
            item_payload["quantity_text"]
        )
        item.note = item_payload.get("note") and str(item_payload["note"])
        item.category_id = category.id if category else None
        item.checked = bool(item_payload.get("checked", False))
        item.hidden_until = None
        item.sort_order = index
        item.updated_by = updated_by.id
        if item.checked:
            checked_by_email = str(item_payload.get("checked_by_email", updated_by.email))
            item.checked_by = users[checked_by_email].id
            item.checked_at = datetime.now(timezone.utc)
        else:
            item.checked_by = None
            item.checked_at = None

    await db.execute(delete(ListCategoryOrder).where(ListCategoryOrder.list_id == grocery_list.id))
    await db.flush()
    for index, category_name in enumerate(payload.get("category_order", [])):
        category = categories.get((household_name, str(category_name))) or categories.get(
            (None, str(category_name))
        )
        if category is None:
            raise ValueError(f"Unknown category {category_name} for list {grocery_list.name}")
        db.add(
            ListCategoryOrder(
                list_id=grocery_list.id,
                category_id=category.id,
                sort_order=index,
            )
        )


async def ensure_seed_data(db: AsyncSession, fixture_path: str) -> None:
    payload = _load_fixture(fixture_path)
    users_payload = payload.get("users", [])
    if not isinstance(users_payload, list):
        raise ValueError("Seed fixture users must be a list")

    households_payload = payload.get("households", [])
    if not isinstance(households_payload, list):
        raise ValueError("Seed fixture households must be a list")

    categories_payload = payload.get("categories", [])
    if not isinstance(categories_payload, list):
        raise ValueError("Seed fixture categories must be a list")

    users = await _resolve_users(db, [dict(entry) for entry in users_payload])
    households: dict[str, Household] = {}
    for household_payload in households_payload:
        household = await _ensure_household(db, households, users, dict(household_payload))
        members_payload = household_payload.get("members", [])
        if not isinstance(members_payload, list):
            raise ValueError(f"Household members for {household.name} must be a list")
        for member_payload in members_payload:
            member_user = users[str(member_payload["email"])]
            await _ensure_member(
                db, household, member_user, str(member_payload.get("role", "editor"))
            )
        await _ensure_member(db, household, users[str(household_payload["owner_email"])], "owner")

    preview_member = users.get(PREVIEW_MEMBER_EMAIL)
    preview_admin = users.get(PREVIEW_INSTANCE_ADMIN_EMAIL)
    if preview_member is not None:
        for household in households.values():
            role = "owner" if household.owner_user_id == preview_member.id else "editor"
            await _ensure_member(db, household, preview_member, role)
    if preview_admin is not None:
        await db.execute(delete(HouseholdMember).where(HouseholdMember.user_id == preview_admin.id))

    categories: dict[tuple[str | None, str], Category] = {}
    for category_payload in categories_payload:
        category = await _ensure_category(db, households, dict(category_payload))
        categories[
            (
                category_payload.get("household") and str(category_payload["household"]),
                category.name,
            )
        ] = category

    for household_payload in households_payload:
        household = households[str(household_payload["name"])]
        lists_payload = household_payload.get("lists", [])
        if not isinstance(lists_payload, list):
            raise ValueError(f"Household lists for {household.name} must be a list")
        for list_payload in lists_payload:
            grocery_list = await _ensure_list(db, household, users, dict(list_payload))
            await _seed_list_items(
                db,
                grocery_list,
                users,
                categories,
                household.name,
                dict(list_payload),
            )

    await db.commit()
