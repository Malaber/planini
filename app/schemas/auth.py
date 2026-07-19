from uuid import UUID

from pydantic import BaseModel, EmailStr


class UITestBootstrapRequest(BaseModel):
    email: EmailStr


class UITestBootstrapOut(BaseModel):
    access_token: str
    display_name: str
    user_id: UUID
