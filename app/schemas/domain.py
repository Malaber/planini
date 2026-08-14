from datetime import UTC, datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.common import ORMModel

SALE_WINDOW_FIELDS = frozenset({"sale_starts_at", "sale_ends_at"})


class GroceryItemSaleWindowInput(BaseModel):
    sale_starts_at: datetime | None = None
    sale_ends_at: datetime | None = None

    @field_validator("sale_starts_at", "sale_ends_at")
    @classmethod
    def normalize_sale_datetime(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.utcoffset() is None:
            raise ValueError("Sale schedule datetimes must include a timezone offset.")
        return value.astimezone(UTC)

    @model_validator(mode="after")
    def validate_sale_window(self) -> "GroceryItemSaleWindowInput":
        provided_fields = self.model_fields_set & SALE_WINDOW_FIELDS
        if provided_fields and provided_fields != SALE_WINDOW_FIELDS:
            raise ValueError("sale_starts_at and sale_ends_at must be provided together.")
        if (self.sale_starts_at is None) != (self.sale_ends_at is None):
            raise ValueError(
                "sale_starts_at and sale_ends_at must both be null or both be datetimes."
            )
        if (
            self.sale_starts_at is not None
            and self.sale_ends_at is not None
            and self.sale_starts_at >= self.sale_ends_at
        ):
            raise ValueError("sale_starts_at must be before sale_ends_at.")
        return self


class HouseholdCreate(BaseModel):
    name: str


class HouseholdOut(ORMModel):
    id: UUID
    name: str


class HouseholdInviteCreate(BaseModel):
    expires_in_hours: int | None = Field(default=24, ge=1, le=24 * 30)
    max_uses: int | None = Field(default=None, ge=1, le=100)

    @model_validator(mode="after")
    def require_expiration_or_use_limit(self) -> "HouseholdInviteCreate":
        if self.expires_in_hours is None and self.max_uses is None:
            raise ValueError("Invite links must expire or have a usage limit.")
        return self


class HouseholdInviteOut(BaseModel):
    invite_url: str
    expires_at: datetime | None
    max_uses: int | None = None


class HouseholdInvitePreviewOut(BaseModel):
    household_id: UUID
    household_name: str
    expires_at: datetime | None
    max_uses: int | None = None
    remaining_uses: int | None = None
    already_member: bool


class GroceryListCreate(BaseModel):
    name: str
    accent_color: str | None = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$")


class GroceryListUpdate(BaseModel):
    name: str | None = None
    accent_color: str | None = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$")


class GroceryListOut(ORMModel):
    id: UUID
    household_id: UUID
    name: str
    accent_color: str | None
    archived: bool
    open_item_count: int = 0


class PublicGroceryListOut(GroceryListOut):
    expires_at: datetime


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    color: str | None = None
    aliases: list[str] = Field(default_factory=list)
    translations: dict[str, str] = Field(default_factory=dict)


class CategoryOut(ORMModel):
    id: UUID
    household_id: UUID | None
    name: str
    color: str | None
    aliases: list[str]
    translations: dict[str, str]


class ListCategoryOrderUpdate(BaseModel):
    category_ids: list[UUID]


class ListCategoryOrderOut(BaseModel):
    category_id: UUID
    sort_order: int


class ListDisabledCategoriesUpdate(BaseModel):
    category_ids: list[UUID]


class ListDisabledCategoriesOut(BaseModel):
    category_ids: list[UUID]


class GroceryItemCreate(GroceryItemSaleWindowInput):
    name: str
    quantity_text: str | None = None
    note: str | None = None
    category_id: UUID | None = None
    sort_order: int = 0


class GroceryItemUpdate(GroceryItemSaleWindowInput):
    name: str | None = None
    list_id: UUID | None = None
    quantity_text: str | None = None
    note: str | None = None
    category_id: UUID | None = None
    sort_order: int | None = None
    hidden_until: datetime | None = None


class GroceryItemOut(ORMModel):
    id: UUID
    list_id: UUID
    name: str
    quantity_text: str | None
    note: str | None
    category_id: UUID | None
    checked: bool
    checked_at: datetime | None
    checked_state_recorded_at: datetime | None
    hidden_until: datetime | None
    sale_starts_at: datetime | None
    sale_ends_at: datetime | None
    sort_order: int

    @field_validator("sale_starts_at", "sale_ends_at")
    @classmethod
    def normalize_stored_sale_datetime(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.utcoffset() is None:
            value = value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


class GroceryItemsWindowOut(BaseModel):
    items: list[GroceryItemOut]
    checked_remaining_count: int


class GroceryItemOfflineMutation(BaseModel):
    mutation_id: str
    type: str
    item_id: UUID | str | None = None
    client_item_id: str | None = None
    recorded_at: datetime
    payload: dict[str, object | None] | None = None
    checked: bool | None = None


class GroceryItemOfflineSyncIn(BaseModel):
    mutations: list[GroceryItemOfflineMutation] = Field(default_factory=list)


class GroceryItemOfflineSyncOut(BaseModel):
    items: list[GroceryItemOut]
    deleted_item_ids: list[str] = Field(default_factory=list)
    client_item_ids: dict[str, UUID] = Field(default_factory=dict)
    applied_mutation_ids: list[str] = Field(default_factory=list)


class PublicListLinkCreate(BaseModel):
    expires_in_days: int = Field(ge=1, le=30)


class PublicListLinkOut(BaseModel):
    public_url: str
    expires_at: datetime
