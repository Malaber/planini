from uuid import UUID

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models import GroceryList, HouseholdMember, User
from app.services.auth_sessions import get_session_user

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login/verify", auto_error=False)


async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db),
    token: str | None = Depends(oauth2_scheme),
) -> User:
    if token:
        raw_token = token
    else:
        session_user = await get_session_user(request, db)
        if session_user is not None:
            return session_user
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)

    try:
        payload = jwt.decode(raw_token, settings.secret_key, algorithms=[settings.algorithm])
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        user_uuid = UUID(user_id)
    except (JWTError, ValueError, TypeError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED) from exc
    result = await db.execute(select(User).where(User.id == user_uuid))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return user


def ensure_admin_user(user: User) -> None:
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)


def ensure_non_admin_user(user: User) -> None:
    if user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)


async def require_admin_user(user: User = Depends(get_current_user)) -> User:
    ensure_admin_user(user)
    return user


async def require_non_admin_user(user: User = Depends(get_current_user)) -> User:
    ensure_non_admin_user(user)
    return user


async def get_household_membership(
    db: AsyncSession, household_id: UUID, user_id: UUID
) -> HouseholdMember:
    result = await db.execute(
        select(HouseholdMember).where(
            HouseholdMember.household_id == household_id,
            HouseholdMember.user_id == user_id,
        )
    )
    membership = result.scalar_one_or_none()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN)
    return membership


async def ensure_household_member(
    db: AsyncSession, household_id: UUID, user_id: UUID
) -> HouseholdMember:
    return await get_household_membership(db, household_id, user_id)


async def ensure_household_editor(
    db: AsyncSession, household_id: UUID, user_id: UUID
) -> HouseholdMember:
    membership = await get_household_membership(db, household_id, user_id)
    if membership.role not in {"owner", "editor"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires editor access.",
        )
    return membership


async def ensure_household_owner(
    db: AsyncSession, household_id: UUID, user_id: UUID
) -> HouseholdMember:
    membership = await get_household_membership(db, household_id, user_id)
    if membership.role != "owner":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the household owner can perform this action.",
        )
    return membership


async def get_list_for_user(db: AsyncSession, list_id: UUID, user_id: UUID) -> GroceryList:
    result = await db.execute(select(GroceryList).where(GroceryList.id == list_id))
    grocery_list = result.scalar_one_or_none()
    if grocery_list is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    await ensure_household_member(db, grocery_list.household_id, user_id)
    return grocery_list


async def get_list_for_editor(db: AsyncSession, list_id: UUID, user_id: UUID) -> GroceryList:
    grocery_list = await get_list_for_user(db, list_id, user_id)
    await ensure_household_editor(db, grocery_list.household_id, user_id)
    return grocery_list


async def get_list_for_owner(db: AsyncSession, list_id: UUID, user_id: UUID) -> GroceryList:
    grocery_list = await get_list_for_user(db, list_id, user_id)
    await ensure_household_owner(db, grocery_list.household_id, user_id)
    return grocery_list
