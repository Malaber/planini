from datetime import timedelta

from fastapi import Depends, HTTPException, Request, status
from fastpasskey import FastPasskey, PasskeyRouterConfig, create_passkey_router
from sqlalchemy.ext.asyncio import AsyncSession
from webauthn import verify_authentication_response, verify_registration_response

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.security import create_access_token
from app.schemas.auth import UITestBootstrapOut, UITestBootstrapRequest
from app.services.passkey_repository import (
    get_passkey_repository,
    load_user_with_passkeys_by_email,
)


def _passkey_service() -> FastPasskey:
    return FastPasskey(
        rp_name=settings.app_name,
        rp_id=settings.webauthn_rp_id,
        origin=settings.app_base_url,
        flow_ttl=timedelta(seconds=settings.auth_flow_expire_seconds),
        registration_verifier=verify_registration_response,
        authentication_verifier=verify_authentication_response,
    )


router = create_passkey_router(
    PasskeyRouterConfig(
        service_factory=_passkey_service,
        repository_dependency=get_passkey_repository,
        current_user_dependency=get_current_user,
    )
)


def _is_loopback_host(hostname: str | None) -> bool:
    return hostname in {"localhost", "127.0.0.1", "::1"}


@router.post("/ui-test-bootstrap", response_model=UITestBootstrapOut)
async def ui_test_bootstrap(
    payload: UITestBootstrapRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> UITestBootstrapOut:
    if settings.ui_test_bootstrap_enabled is False or not _is_loopback_host(request.url.hostname):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    user = await load_user_with_passkeys_by_email(db, str(payload.email))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    return UITestBootstrapOut(
        access_token=create_access_token(user.id),
        display_name=user.display_name,
        user_id=user.id,
    )
