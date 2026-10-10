import json
import uuid

from sqlalchemy import ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    household_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("households.id"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    color: Mapped[str | None] = mapped_column(String(30), nullable=True)
    aliases_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    translations_text: Mapped[str] = mapped_column(Text, nullable=False, default="{}")

    @property
    def aliases(self) -> list[str]:
        return [alias.strip() for alias in self.aliases_text.splitlines() if alias.strip()]

    @aliases.setter
    def aliases(self, value: list[str]) -> None:
        self.aliases_text = "\n".join(alias.strip() for alias in value if alias.strip())

    @property
    def translations(self) -> dict[str, str]:
        values = json.loads(self.translations_text or "{}")
        return {
            str(locale): str(value).strip()
            for locale, value in values.items()
            if str(value).strip()
        }

    @translations.setter
    def translations(self, value: dict[str, str]) -> None:
        normalized = {
            str(locale): str(translation).strip()
            for locale, translation in value.items()
            if str(translation).strip()
        }
        self.translations_text = json.dumps(normalized, ensure_ascii=False, sort_keys=True)

    def localized_name(self, locale: str) -> str:
        return self.translations.get(locale, self.name)
