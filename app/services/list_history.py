from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ListHistoryEntry, User


def record_list_history(
    db: AsyncSession,
    *,
    household_id: UUID,
    list_id: UUID | None,
    actor: User,
    event_type: str,
    subject_id: UUID | None = None,
    subject_name: str | None = None,
    details: dict[str, str | None] | None = None,
    occurred_at: datetime | None = None,
) -> ListHistoryEntry:
    entry = ListHistoryEntry(
        household_id=household_id,
        list_id=list_id,
        actor_user_id=actor.id,
        actor_display_name=actor.display_name,
        event_type=event_type,
        subject_id=subject_id,
        subject_name=subject_name,
        details=details or {},
        created_at=occurred_at or datetime.now(UTC),
    )
    db.add(entry)
    return entry
