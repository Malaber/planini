from collections.abc import Iterable, Mapping
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastpasskey import (
    CeremonyStart,
    FastPasskey,
    PasskeyConfigurationError,
    PasskeyNameError,
    PasskeyPayloadError,
    PasskeyUser,
    ceremony_state_is_valid,
    credential_id_from_payload,
    default_passkey_name,
    expected_origins,
    new_ceremony_state,
    validate_passkey_name,
)
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from webauthn import verify_authentication_response, verify_registration_response
from webauthn.helpers import bytes_to_base64url

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.security import create_access_token
from app.models import Passkey, User
from app.services.auth_sessions import create_auth_session, revoke_auth_session
from app.services.passkey_reset import (
    clear_passkey_reset,
    get_passkey_add_link_for_token,
    get_user_for_passkey_reset_token,
)
from app.schemas.auth import (
    PasskeyFinishRequest,
    PasskeyLoginStartRequest,
    PasskeyNameRequest,
    PasskeyOut,
    PasskeyRegisterStartRequest,
    PasswordAuthRequest,
    TokenOut,
    UITestBootstrapOut,
    UITestBootstrapRequest,
    UserOut,
)

router = APIRouter(prefix="/auth", tags=["auth"])

_REGISTER_SESSION_KEY = "passkey_register"
_LOGIN_SESSION_KEY = "passkey_login"
_SETTINGS_SESSION_KEY = "passkey_settings"
_PASSKEY_ADD_SESSION_KEY = "passkey_add"
_PASSKEY_DELETE_SESSION_KEY = "passkey_delete"
_PASSKEY_RENAME_SESSION_KEY = "passkey_rename"
_PASSKEY_RESET_SESSION_KEY = "passkey_add_link"
_DEFAULT_INITIAL_PASSKEY_NAME = "Passkey 1"
_REGISTRATION_FAILURE_DETAIL = (
    "Could not create that account. Try signing in with an existing "
    "passkey or use a different email."
)

_expected_origins = expected_origins


def _new_passkey(
    *,
    name: str,
    credential_id: str,
    public_key: bytes,
    sign_count: int,
    user_id: UUID | None = None,
) -> Passkey:
    created_at = datetime.now(UTC)
    passkey = Passkey(
        name=name,
        credential_id=credential_id,
        public_key=public_key,
        sign_count=sign_count,
        created_at=created_at,
        last_used_at=created_at,
    )
    if user_id is not None:
        passkey.user_id = user_id
    return passkey


def _is_loopback_host(hostname: str | None) -> bool:
    return hostname in {"localhost", "127.0.0.1", "::1"}


def _passkey_service() -> FastPasskey:
    return FastPasskey(
        rp_name=settings.app_name,
        rp_id=settings.webauthn_rp_id,
        origin=settings.app_base_url,
        flow_ttl=timedelta(seconds=settings.auth_flow_expire_seconds),
        registration_verifier=verify_registration_response,
        authentication_verifier=verify_authentication_response,
    )


def _passkey_context(request: Request) -> tuple[str, str]:
    try:
        return _passkey_service().resolve_context(
            request_host=request.url.hostname,
            request_base_url=str(request.base_url),
        )
    except PasskeyConfigurationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _rp_id_for_request(request: Request) -> str:
    return _passkey_context(request)[0]


def _origin_for_request(request: Request) -> str:
    return _passkey_context(request)[1]


def _begin_registration(
    request: Request,
    *,
    user_id: UUID,
    email: str,
    display_name: str,
    exclude_credential_ids: Iterable[str] = (),
    state_payload: Mapping[str, object] | None = None,
) -> CeremonyStart:
    try:
        return _passkey_service().begin_registration(
            user=PasskeyUser(
                id=user_id.bytes,
                name=email,
                display_name=display_name,
            ),
            request_host=request.url.hostname,
            request_base_url=str(request.base_url),
            exclude_credential_ids=exclude_credential_ids,
            state_payload=state_payload,
        )
    except PasskeyConfigurationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _begin_authentication(
    request: Request,
    *,
    allow_credential_ids: Iterable[str] | None = None,
    state_payload: Mapping[str, object] | None = None,
) -> CeremonyStart:
    try:
        return _passkey_service().begin_authentication(
            request_host=request.url.hostname,
            request_base_url=str(request.base_url),
            allow_credential_ids=allow_credential_ids,
            state_payload=state_payload,
        )
    except PasskeyConfigurationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _password_auth_disabled() -> HTTPException:
    return HTTPException(
        status_code=400,
        detail="Password-based auth is disabled. Use the passkey registration and login endpoints.",
    )


def _credential_id_from_payload(payload: PasskeyFinishRequest) -> str:
    try:
        return credential_id_from_payload(payload.credential)
    except PasskeyPayloadError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _new_auth_flow_session(**payload: object) -> dict[str, object]:
    return new_ceremony_state(**payload)


def _auth_flow_session_is_valid(pending: dict[str, object] | None) -> bool:
    return ceremony_state_is_valid(
        pending,
        ttl=timedelta(seconds=settings.auth_flow_expire_seconds),
    )


async def _load_user_with_passkeys(db: AsyncSession, user_id: UUID) -> User | None:
    result = await db.execute(
        select(User).options(selectinload(User.passkeys)).where(User.id == user_id)
    )
    return result.scalar_one_or_none()


async def _load_user_with_passkeys_by_email(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(
        select(User).options(selectinload(User.passkeys)).where(User.email == email)
    )
    return result.scalar_one_or_none()


async def _load_passkey_with_user_by_credential_id(
    db: AsyncSession, credential_id: str
) -> Passkey | None:
    result = await db.execute(
        select(Passkey)
        .options(selectinload(Passkey.user))
        .where(Passkey.credential_id == credential_id)
    )
    return result.scalar_one_or_none()


def _validated_passkey_name(raw_name: str) -> str:
    try:
        return validate_passkey_name(raw_name)
    except PasskeyNameError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _default_passkey_name_for_count(existing_count: int) -> str:
    return default_passkey_name(existing_count)


async def _apply_bootstrap_admin_email(db: AsyncSession, user: User) -> User:
    if settings.bootstrap_admin_email is None:
        return user

    if user.email.casefold() != str(settings.bootstrap_admin_email).casefold():
        return user

    if user.is_admin:
        return user

    user.is_admin = True
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/register/options")
async def begin_passkey_registration(
    payload: PasskeyRegisterStartRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> dict:
    user_id = uuid4()
    start = _begin_registration(
        request,
        user_id=user_id,
        email=payload.email,
        display_name=payload.display_name,
        state_payload={
            "email": payload.email,
            "display_name": payload.display_name,
            "user_id": str(user_id),
        },
    )
    request.session[_REGISTER_SESSION_KEY] = start.state
    return start.options


@router.post("/register/verify", response_model=UserOut)
async def finish_passkey_registration(
    payload: PasskeyFinishRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> User:
    pending = request.session.get(_REGISTER_SESSION_KEY)
    if not _auth_flow_session_is_valid(pending):
        request.session.pop(_REGISTER_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Registration session expired")

    existing = await _load_user_with_passkeys_by_email(db, pending["email"])
    if existing is not None:
        raise HTTPException(status_code=400, detail=_REGISTRATION_FAILURE_DETAIL)

    try:
        verified = _passkey_service().verify_registration(
            credential=payload.credential,
            state=pending,
        )
    except Exception as exc:  # pragma: no cover - exercised via API tests with monkeypatch
        raise HTTPException(status_code=400, detail="Passkey registration failed") from exc

    credential_id = bytes_to_base64url(verified.credential_id)
    if (
        await db.execute(select(Passkey).where(Passkey.credential_id == credential_id))
    ).scalar_one_or_none() is not None:
        raise HTTPException(status_code=400, detail=_REGISTRATION_FAILURE_DETAIL)

    user = User(
        id=UUID(pending["user_id"]),
        email=pending["email"],
        password_hash="",
        display_name=pending["display_name"],
    )
    user.passkeys.append(
        _new_passkey(
            name=_DEFAULT_INITIAL_PASSKEY_NAME,
            credential_id=credential_id,
            public_key=verified.credential_public_key,
            sign_count=verified.sign_count,
        )
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail=_REGISTRATION_FAILURE_DETAIL) from exc
    await db.refresh(user)
    user = await _apply_bootstrap_admin_email(db, user)

    await create_auth_session(request, db, user)
    return user


@router.post("/login/options")
async def begin_passkey_login(_: PasskeyLoginStartRequest, request: Request) -> dict:
    start = _begin_authentication(request)
    request.session[_LOGIN_SESSION_KEY] = start.state
    return start.options


@router.post("/login/verify", response_model=TokenOut)
async def finish_passkey_login(
    payload: PasskeyFinishRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> TokenOut:
    pending = request.session.get(_LOGIN_SESSION_KEY)
    if not _auth_flow_session_is_valid(pending):
        request.session.pop(_LOGIN_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Login session expired")

    credential_id = _credential_id_from_payload(payload)
    passkey = await _load_passkey_with_user_by_credential_id(db, credential_id)
    if passkey is None:
        raise HTTPException(status_code=404, detail="No passkey found for that credential")
    user = passkey.user
    if user is None:
        raise HTTPException(status_code=404, detail="No user found for that passkey")

    try:
        verified = _passkey_service().verify_authentication(
            credential=payload.credential,
            state=pending,
            credential_public_key=passkey.public_key,
            credential_current_sign_count=passkey.sign_count,
        )
    except Exception as exc:  # pragma: no cover - exercised via API tests with monkeypatch
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid passkey",
        ) from exc

    passkey.sign_count = verified.new_sign_count
    passkey.last_used_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(passkey)
    await db.refresh(user)
    user = await _apply_bootstrap_admin_email(db, user)

    token = create_access_token(user.id)
    await create_auth_session(request, db, user)
    return TokenOut(access_token=token)


@router.post("/settings/passkey/options")
async def begin_passkey_replace(
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    start = _begin_registration(
        request,
        user_id=refreshed.id,
        email=refreshed.email,
        display_name=refreshed.display_name,
        exclude_credential_ids=(passkey.credential_id for passkey in refreshed.passkeys),
        state_payload={"user_id": str(refreshed.id)},
    )
    request.session[_SETTINGS_SESSION_KEY] = start.state
    return start.options


@router.post("/settings/passkey/verify", response_model=UserOut)
async def finish_passkey_replace(
    payload: PasskeyFinishRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    pending = request.session.get(_SETTINGS_SESSION_KEY)
    if not _auth_flow_session_is_valid(pending) or pending.get("user_id") != str(user.id):
        request.session.pop(_SETTINGS_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey settings session expired")

    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        verified = _passkey_service().verify_registration(
            credential=payload.credential,
            state=pending,
        )
    except Exception as exc:  # pragma: no cover - exercised via API tests with monkeypatch
        raise HTTPException(status_code=400, detail="Passkey update failed") from exc

    credential_id = bytes_to_base64url(verified.credential_id)
    if (
        await db.execute(select(Passkey).where(Passkey.credential_id == credential_id))
    ).scalar_one_or_none() is not None:
        raise HTTPException(status_code=400, detail="That passkey is already registered")

    await db.execute(delete(Passkey).where(Passkey.user_id == refreshed.id))
    db.add(
        _new_passkey(
            user_id=refreshed.id,
            name=_DEFAULT_INITIAL_PASSKEY_NAME,
            credential_id=credential_id,
            public_key=verified.credential_public_key,
            sign_count=verified.sign_count,
        )
    )
    await db.commit()
    await db.refresh(refreshed)
    request.session.pop(_SETTINGS_SESSION_KEY, None)
    return refreshed


@router.post("/register", response_model=None)
async def register_password_disabled(_: PasswordAuthRequest) -> None:
    raise _password_auth_disabled()


@router.post("/login", response_model=None)
async def login_password_disabled(_: PasswordAuthRequest) -> None:
    raise _password_auth_disabled()


@router.post("/logout")
async def logout(request: Request, db: AsyncSession = Depends(get_db)) -> dict[str, str]:
    await revoke_auth_session(request, db)
    request.session.clear()
    return {"message": "logged out"}


@router.get("/passkeys", response_model=list[PasskeyOut])
async def list_passkeys(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[Passkey]:
    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")
    return refreshed.passkeys


@router.post("/passkeys/register/options")
async def begin_add_passkey(
    payload: PasskeyNameRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")
    passkey_name = _validated_passkey_name(payload.name)

    start = _begin_registration(
        request,
        user_id=refreshed.id,
        email=refreshed.email,
        display_name=refreshed.display_name,
        exclude_credential_ids=(passkey.credential_id for passkey in refreshed.passkeys),
        state_payload={
            "user_id": str(refreshed.id),
            "name": passkey_name,
        },
    )
    request.session[_PASSKEY_ADD_SESSION_KEY] = start.state
    return start.options


@router.post("/passkeys/register/verify", response_model=PasskeyOut)
async def finish_add_passkey(
    payload: PasskeyFinishRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Passkey:
    pending = request.session.get(_PASSKEY_ADD_SESSION_KEY)
    if not _auth_flow_session_is_valid(pending):
        request.session.pop(_PASSKEY_ADD_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey registration session expired")
    if pending.get("user_id") != str(user.id):
        request.session.pop(_PASSKEY_ADD_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey registration session expired")

    try:
        verified = _passkey_service().verify_registration(
            credential=payload.credential,
            state=pending,
        )
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=400, detail="Passkey registration failed") from exc

    credential_id = bytes_to_base64url(verified.credential_id)
    if (
        await db.execute(select(Passkey).where(Passkey.credential_id == credential_id))
    ).scalar_one_or_none() is not None:
        raise HTTPException(status_code=400, detail="That passkey is already registered")

    passkey = _new_passkey(
        user_id=user.id,
        name=pending["name"],
        credential_id=credential_id,
        public_key=verified.credential_public_key,
        sign_count=verified.sign_count,
    )
    db.add(passkey)
    await db.commit()
    await db.refresh(passkey)
    request.session.pop(_PASSKEY_ADD_SESSION_KEY, None)
    return passkey


@router.post("/passkey-add/{token}/options")
async def begin_passkey_add_from_link(
    token: str, request: Request, db: AsyncSession = Depends(get_db)
) -> dict[str, object]:
    user = await get_user_for_passkey_reset_token(db, token)
    if user is None:
        raise HTTPException(status_code=404, detail="Passkey add link not found")

    start = _begin_registration(
        request,
        user_id=user.id,
        email=user.email,
        display_name=user.display_name,
        state_payload={
            "user_id": str(user.id),
            "token": token,
        },
    )
    request.session[_PASSKEY_RESET_SESSION_KEY] = start.state
    return start.options


@router.post("/passkey-add/{token}/verify", response_model=UserOut)
async def finish_passkey_add_from_link(
    token: str, payload: PasskeyFinishRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> User:
    pending = request.session.get(_PASSKEY_RESET_SESSION_KEY)
    if not _auth_flow_session_is_valid(pending) or pending.get("token") != token:
        request.session.pop(_PASSKEY_RESET_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey add session expired")

    link = await get_passkey_add_link_for_token(db, token, with_passkeys=True)
    if link is None or pending.get("user_id") != str(link.user.id):
        request.session.pop(_PASSKEY_RESET_SESSION_KEY, None)
        raise HTTPException(status_code=404, detail="Passkey add link not found")
    user = link.user

    try:
        verified = _passkey_service().verify_registration(
            credential=payload.credential,
            state=pending,
        )
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=400, detail="Passkey add failed") from exc

    credential_id = bytes_to_base64url(verified.credential_id)
    existing_passkey = (
        await db.execute(select(Passkey).where(Passkey.credential_id == credential_id))
    ).scalar_one_or_none()
    if existing_passkey is not None:
        raise HTTPException(status_code=400, detail="That passkey is already registered")

    db.add(
        _new_passkey(
            user_id=user.id,
            name=_default_passkey_name_for_count(len(user.passkeys)),
            credential_id=credential_id,
            public_key=verified.credential_public_key,
            sign_count=verified.sign_count,
        )
    )
    clear_passkey_reset(link)
    await db.commit()
    await db.refresh(user)
    request.session.pop(_PASSKEY_RESET_SESSION_KEY, None)
    await create_auth_session(request, db, user)
    return user


@router.post("/passkeys/{passkey_id}/rename/options")
async def begin_rename_passkey(
    passkey_id: UUID,
    payload: PasskeyNameRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    target = next((entry for entry in refreshed.passkeys if entry.id == passkey_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Passkey not found")

    start = _begin_authentication(
        request,
        allow_credential_ids=[target.credential_id],
        state_payload={
            "user_id": str(user.id),
            "passkey_id": str(passkey_id),
            "name": _validated_passkey_name(payload.name),
        },
    )
    request.session[_PASSKEY_RENAME_SESSION_KEY] = start.state
    return start.options


@router.post("/passkeys/{passkey_id}/rename/verify", response_model=PasskeyOut)
async def finish_rename_passkey(
    passkey_id: UUID,
    payload: PasskeyFinishRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Passkey:
    pending = request.session.get(_PASSKEY_RENAME_SESSION_KEY)
    if (
        not _auth_flow_session_is_valid(pending)
        or pending.get("user_id") != str(user.id)
        or pending.get("passkey_id") != str(passkey_id)
    ):
        request.session.pop(_PASSKEY_RENAME_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey rename session expired")

    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    target = next((entry for entry in refreshed.passkeys if entry.id == passkey_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Passkey not found")

    credential_id = payload.credential.get("id")
    if credential_id != target.credential_id:
        raise HTTPException(
            status_code=400,
            detail="Confirm the rename with the passkey you are renaming",
        )

    try:
        verified = _passkey_service().verify_authentication(
            credential=payload.credential,
            state=pending,
            credential_public_key=target.public_key,
            credential_current_sign_count=target.sign_count,
        )
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not verify that passkey before renaming",
        ) from exc

    target.name = pending["name"]
    target.sign_count = verified.new_sign_count
    target.last_used_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(target)
    request.session.pop(_PASSKEY_RENAME_SESSION_KEY, None)
    return target


@router.post("/passkeys/{passkey_id}/delete/options")
async def begin_delete_passkey(
    passkey_id: UUID,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    target = next((entry for entry in refreshed.passkeys if entry.id == passkey_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Passkey not found")
    if len(refreshed.passkeys) <= 1:
        raise HTTPException(status_code=400, detail="You cannot delete your last passkey")

    other_passkeys = [entry for entry in refreshed.passkeys if entry.id != passkey_id]
    start = _begin_authentication(
        request,
        allow_credential_ids=[passkey.credential_id for passkey in other_passkeys],
        state_payload={
            "user_id": str(user.id),
            "passkey_id": str(passkey_id),
        },
    )
    request.session[_PASSKEY_DELETE_SESSION_KEY] = start.state
    return start.options


@router.post("/passkeys/{passkey_id}/delete/verify")
async def finish_delete_passkey(
    passkey_id: UUID,
    payload: PasskeyFinishRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    pending = request.session.get(_PASSKEY_DELETE_SESSION_KEY)
    if (
        not _auth_flow_session_is_valid(pending)
        or pending.get("user_id") != str(user.id)
        or pending.get("passkey_id") != str(passkey_id)
    ):
        request.session.pop(_PASSKEY_DELETE_SESSION_KEY, None)
        raise HTTPException(status_code=400, detail="Passkey deletion session expired")

    refreshed = await _load_user_with_passkeys(db, user.id)
    if refreshed is None:
        raise HTTPException(status_code=404, detail="User not found")

    target = next((entry for entry in refreshed.passkeys if entry.id == passkey_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail="Passkey not found")
    if len(refreshed.passkeys) <= 1:
        raise HTTPException(status_code=400, detail="You cannot delete your last passkey")

    credential_id = _credential_id_from_payload(payload)
    confirming_passkey = next(
        (
            entry
            for entry in refreshed.passkeys
            if entry.credential_id == credential_id and entry.id != passkey_id
        ),
        None,
    )
    if confirming_passkey is None:
        raise HTTPException(
            status_code=400, detail="Confirm deletion with one of your other passkeys"
        )

    try:
        verified = _passkey_service().verify_authentication(
            credential=payload.credential,
            state=pending,
            credential_public_key=confirming_passkey.public_key,
            credential_current_sign_count=confirming_passkey.sign_count,
        )
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not verify another passkey before deletion",
        ) from exc

    confirming_passkey.sign_count = verified.new_sign_count
    confirming_passkey.last_used_at = datetime.now(UTC)
    await db.flush()

    await db.execute(delete(Passkey).where(Passkey.id == passkey_id, Passkey.user_id == user.id))
    await db.commit()
    request.session.pop(_PASSKEY_DELETE_SESSION_KEY, None)
    return {"message": "passkey deleted"}


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)) -> User:
    return user


@router.post("/ui-test-bootstrap", response_model=UITestBootstrapOut)
async def ui_test_bootstrap(
    payload: UITestBootstrapRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> UITestBootstrapOut:
    if settings.ui_test_bootstrap_enabled is False or not _is_loopback_host(request.url.hostname):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    user = await _load_user_with_passkeys_by_email(db, payload.email)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    return UITestBootstrapOut(
        access_token=create_access_token(user.id),
        display_name=user.display_name,
        user_id=user.id,
    )
