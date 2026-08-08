from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.schemas.common import ORMModel


class HouseholdCreate(BaseModel):
    name: str


class HouseholdOut(ORMModel):
    id: UUID
    name: str
    role: Literal["owner", "editor", "viewer"]


class HouseholdInviteCreate(BaseModel):
    expires_in_hours: int | None = Field(default=24, ge=1, le=24 * 30)
    max_uses: int | None = Field(default=None, ge=1, le=100)
    role: Literal["editor", "viewer"] = "editor"

    @model_validator(mode="after")
    def require_expiration_or_use_limit(self) -> "HouseholdInviteCreate":
        if self.expires_in_hours is None and self.max_uses is None:
            raise ValueError("Invite links must expire or have a usage limit.")
        return self


class HouseholdInviteOut(BaseModel):
    invite_url: str
    expires_at: datetime | None
    max_uses: int | None = None
    role: Literal["editor", "viewer"]


class HouseholdInvitePreviewOut(BaseModel):
    household_id: UUID
    household_name: str
    expires_at: datetime | None
    max_uses: int | None = None
    remaining_uses: int | None = None
    already_member: bool
    role: Literal["editor", "viewer"]


class HouseholdMemberOut(BaseModel):
    user_id: UUID
    display_name: str
    email: str
    role: Literal["owner", "editor", "viewer"]


class HouseholdMemberUpdate(BaseModel):
    role: Literal["editor", "viewer"]


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
    access_role: Literal["owner", "editor", "viewer"] = "viewer"


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


class GroceryItemCreate(BaseModel):
    name: str
    quantity_text: str | None = None
    note: str | None = None
    category_id: UUID | None = None
    sort_order: int = 0


class GroceryItemUpdate(BaseModel):
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
    sort_order: int


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
