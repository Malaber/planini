import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import ensure_household_member, get_current_user
from app.core.database import get_db
from app.models import Household, HouseholdInvite, HouseholdInviteUse, HouseholdMember, User
from app.schemas.domain import (
    HouseholdCreate,
    HouseholdInviteCreate,
    HouseholdInviteOut,
    HouseholdInvitePreviewOut,
    HouseholdOut,
)

router = APIRouter(prefix="/households", tags=["households"])


def _hash_invite_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


async def _get_valid_invite(db: AsyncSession, token: str) -> HouseholdInvite:
    result = await db.execute(
        select(HouseholdInvite).where(HouseholdInvite.token_hash == _hash_invite_token(token))
    )
    invite = result.scalar_one_or_none()
    now = datetime.now(UTC)
    if invite is None or (invite.expires_at is not None and _as_utc(invite.expires_at) <= now):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite link is invalid.")
    return invite


async def _remaining_invite_uses(db: AsyncSession, invite: HouseholdInvite) -> int | None:
    if invite.max_uses is None:
        return None
    uses_result = await db.execute(
        select(func.count())
        .select_from(HouseholdInviteUse)
        .where(HouseholdInviteUse.invite_id == invite.id)
    )
    return max(invite.max_uses - uses_result.scalar_one(), 0)


async def _claim_invite_use(db: AsyncSession, invite: HouseholdInvite, user: User) -> None:
    if invite.max_uses is None:
        return
    existing = await db.execute(
        select(HouseholdInviteUse).where(
            HouseholdInviteUse.invite_id == invite.id,
            HouseholdInviteUse.user_id == user.id,
        )
    )
    if existing.scalar_one_or_none() is not None:
        return
    for _ in range(invite.max_uses):
        used_slots = await db.execute(
            select(HouseholdInviteUse.slot_number).where(HouseholdInviteUse.invite_id == invite.id)
        )
        used = set(used_slots.scalars().all())
        slot = next(
            (number for number in range(1, invite.max_uses + 1) if number not in used), None
        )
        if slot is None:
            break
        try:
            async with db.begin_nested():
                db.add(HouseholdInviteUse(invite_id=invite.id, user_id=user.id, slot_number=slot))
                await db.flush()
            return
        except IntegrityError:
            continue
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite link is invalid.")


@router.post("", response_model=HouseholdOut)
async def create_household(
    payload: HouseholdCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Household:
    household = Household(name=payload.name, owner_user_id=user.id)
    db.add(household)
    await db.flush()
    db.add(HouseholdMember(household_id=household.id, user_id=user.id, role="owner"))
    await db.commit()
    await db.refresh(household)
    return household


@router.get("", response_model=list[HouseholdOut])
async def list_households(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[Household]:
    result = await db.execute(
        select(Household).join(HouseholdMember).where(HouseholdMember.user_id == user.id)
    )
    return list(result.scalars().all())


@router.get("/{household_id}", response_model=HouseholdOut)
async def get_household(
    household_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Household:
    await ensure_household_member(db, household_id, user.id)
    result = await db.execute(select(Household).where(Household.id == household_id))
    return result.scalar_one()


@router.post("/{household_id}/invites", response_model=HouseholdInviteOut)
async def create_household_invite(
    household_id: UUID,
    request: Request,
    payload: HouseholdInviteCreate | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HouseholdInviteOut:
    result = await db.execute(select(Household).where(Household.id == household_id))
    household = result.scalar_one_or_none()
    if household is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    await ensure_household_member(db, household_id, user.id)
    if household.owner_user_id != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the household owner can create invite links.",
        )

    invite_options = payload or HouseholdInviteCreate()
    token = secrets.token_urlsafe(32)
    expires_at = (
        datetime.now(UTC) + timedelta(hours=invite_options.expires_in_hours)
        if invite_options.expires_in_hours is not None
        else None
    )
    invite = HouseholdInvite(
        household_id=household_id,
        created_by_user_id=user.id,
        token_hash=_hash_invite_token(token),
        expires_at=expires_at,
        max_uses=invite_options.max_uses,
    )
    db.add(invite)
    await db.commit()

    invite_url = str(request.base_url).rstrip("/") + f"/invite/{token}"
    return HouseholdInviteOut(
        invite_url=invite_url, expires_at=expires_at, max_uses=invite.max_uses
    )


@router.get("/invites/{token}", response_model=HouseholdInvitePreviewOut)
async def get_household_invite(
    token: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HouseholdInvitePreviewOut:
    invite = await _get_valid_invite(db, token)
    household_result = await db.execute(
        select(Household).where(Household.id == invite.household_id)
    )
    household = household_result.scalar_one()
    membership_result = await db.execute(
        select(HouseholdMember).where(
            HouseholdMember.household_id == invite.household_id,
            HouseholdMember.user_id == user.id,
        )
    )
    already_member = membership_result.scalar_one_or_none() is not None
    remaining_uses = await _remaining_invite_uses(db, invite)
    if not already_member and remaining_uses == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite link is invalid.")
    return HouseholdInvitePreviewOut(
        household_id=household.id,
        household_name=household.name,
        expires_at=_as_utc(invite.expires_at) if invite.expires_at is not None else None,
        max_uses=invite.max_uses,
        remaining_uses=remaining_uses,
        already_member=already_member,
    )


@router.post("/invites/{token}/accept", response_model=HouseholdOut)
async def accept_household_invite(
    token: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Household:
    invite = await _get_valid_invite(db, token)
    household_result = await db.execute(
        select(Household).where(Household.id == invite.household_id)
    )
    household = household_result.scalar_one()
    membership_result = await db.execute(
        select(HouseholdMember).where(
            HouseholdMember.household_id == invite.household_id,
            HouseholdMember.user_id == user.id,
        )
    )
    membership = membership_result.scalar_one_or_none()
    if membership is None:
        await _claim_invite_use(db, invite, user)
        db.add(HouseholdMember(household_id=invite.household_id, user_id=user.id, role="member"))

    invite.accepted_at = datetime.now(UTC)
    invite.accepted_by_user_id = user.id
    await db.commit()
    await db.refresh(household)
    return household
