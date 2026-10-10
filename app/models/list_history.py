import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, ForeignKey, Index, JSON, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class ListHistoryEntry(Base):
    __tablename__ = "list_history_entries"
    __table_args__ = (
        Index("ix_list_history_entries_list_created", "list_id", "created_at"),
        Index(
            "ix_list_history_entries_household_created",
            "household_id",
            "created_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("households.id"), nullable=False
    )
    # Deliberately not a foreign key: history survives deletion of its list.
    list_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    # Actor identity and display name are snapshots so user deletion keeps audit context.
    actor_user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    actor_display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    subject_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    subject_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    details: Mapped[dict[str, str | None]] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
