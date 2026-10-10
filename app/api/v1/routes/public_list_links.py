import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_list_for_user
from app.core.database import get_db
from app.models import PublicListLink, User
from app.schemas.domain import PublicListLinkCreate, PublicListLinkOut

router = APIRouter(tags=["public-list-links"])


def hash_public_list_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


async def get_valid_public_list_link(db: AsyncSession, token: str) -> PublicListLink:
    result = await db.execute(
        select(PublicListLink).where(PublicListLink.token_hash == hash_public_list_token(token))
    )
    link = result.scalar_one_or_none()
    now = datetime.now(UTC)
    if link is None or link.revoked_at is not None or _as_utc(link.expires_at) <= now:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Public list link is invalid or expired."
        )
    return link


@router.post("/lists/{list_id}/public-links", response_model=PublicListLinkOut)
async def create_public_list_link(
    list_id: UUID,
    payload: PublicListLinkCreate,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PublicListLinkOut:
    await get_list_for_user(db, list_id, user.id)
    token = secrets.token_urlsafe(32)
    expires_at = datetime.now(UTC) + timedelta(days=payload.expires_in_days)
    db.add(
        PublicListLink(
            list_id=list_id,
            created_by_user_id=user.id,
            token_hash=hash_public_list_token(token),
            expires_at=expires_at,
        )
    )
    await db.commit()
    return PublicListLinkOut(
        public_url=str(request.url_for("public_list_detail", token=token)),
        expires_at=expires_at,
    )
