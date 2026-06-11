import asyncio
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from jose import jwt
from pydantic import ValidationError
from pydantic_settings import BaseSettings, SettingsConfigDict
from starlette.requests import Request

from app.admin import (
    SessionAdminAuth,
    _passkey_add_link_duration_hours,
    get_application_version,
)
from app.api.v1.routes.auth import (
    _auth_flow_session_is_valid,
    _apply_bootstrap_admin_email,
    _new_auth_flow_session,
    _origin_for_request,
    _password_auth_disabled,
    _rp_id_for_request,
)
from app.core.config import (
    ConfigurationError,
    FriendlyEnvSettingsSource,
    Settings,
    _format_invalid_env_value,
    _join_validation_path,
    load_settings,
    settings,
)
from app.core import startup_checks
from app.core.startup_checks import (
    _sqlite_database_path,
    ensure_database_path_writable,
    ensure_required_email_configured,
)
from app.core.security import (
    create_access_token,
    hash_password,
    verify_password,
)
from app.services.auth_sessions import (
    AUTH_SESSION_ID_KEY,
    _as_utc,
    _auth_session_is_valid,
    get_session_user,
    revoke_auth_session,
)
from app.services.passkey_reset import (
    build_passkey_add_link,
    clear_passkey_reset,
    create_passkey_reset_token,
    hash_passkey_reset_token,
    issue_passkey_reset,
    passkey_reset_is_active,
    set_passkey_reset,
)
from app.services.websocket_hub import WebSocketHub


class DummyWebSocket:
    def __init__(self) -> None:
        self.accepted = False
        self.events: list[dict] = []
        self.close_calls = 0

    async def accept(self) -> None:
        self.accepted = True

    async def send_json(self, event: dict) -> None:
        self.events.append(event)

    async def close(self) -> None:
        self.close_calls += 1


class SlowDummyWebSocket(DummyWebSocket):
    def __init__(self) -> None:
        super().__init__()
        self.send_calls = 0

    async def send_json(self, event: dict) -> None:
        self.send_calls += 1
        await asyncio.sleep(60)


class DummySessionContext:
    async def __aenter__(self) -> object:
        return object()

    async def __aexit__(self, exc_type, exc, tb) -> None:
        return None


class DummyDB:
    def __init__(self) -> None:
        self.commit_calls = 0
        self.refresh_calls = 0
        self.added = []

    def add(self, obj) -> None:
        self.added.append(obj)

    async def commit(self) -> None:
        self.commit_calls += 1

    async def refresh(self, user) -> None:
        self.refresh_calls += 1


class DummyScalarResult:
    def __init__(self, value) -> None:
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class DummyAuthSessionDB:
    def __init__(self, auth_session=None) -> None:
        self.auth_session = auth_session
        self.commit_calls = 0
        self.deleted = []

    async def get(self, model, session_id):
        return self.auth_session

    async def delete(self, auth_session) -> None:
        self.deleted.append(auth_session)

    async def commit(self) -> None:
        self.commit_calls += 1

    async def execute(self, query):
        return DummyScalarResult(self.auth_session)


def test_security_helpers_round_trip() -> None:
    password = "hello"
    password_hash = hash_password(password)
    assert verify_password(password, password_hash)
    assert not verify_password("bad", password_hash)
    assert isinstance(create_access_token(uuid4()), str)


def test_access_token_expiry_uses_configured_window() -> None:
    token = create_access_token(uuid4())
    payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    expires_at = datetime.fromtimestamp(payload["exp"], UTC)
    delta = expires_at - datetime.now(UTC)
    assert delta > timedelta(days=27, hours=23)
    assert delta < timedelta(days=28, minutes=1)


def test_passkey_reset_helpers_manage_token_state() -> None:
    token = create_passkey_reset_token()
    user = SimpleNamespace(id=uuid4())

    assert len(hash_passkey_reset_token(token)) == 64

    link = set_passkey_reset(user, token)
    assert link.user_id == user.id
    assert link.token_hash == hash_passkey_reset_token(token)
    assert link.used_at is None
    assert passkey_reset_is_active(link) is True

    link.expires_at = link.expires_at.replace(tzinfo=None)
    assert passkey_reset_is_active(link) is True

    link.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    assert passkey_reset_is_active(link) is False

    link.expires_at = datetime.now(UTC) + timedelta(hours=1)
    clear_passkey_reset(link)
    assert link.used_at is not None
    assert passkey_reset_is_active(link) is False
    assert link.is_active() is False

    link.used_at = None
    link.token_hash = ""
    assert passkey_reset_is_active(link) is False


def test_passkey_reset_helpers_accept_custom_ttl() -> None:
    token = create_passkey_reset_token()
    user = SimpleNamespace(id=uuid4())

    link = set_passkey_reset(user, token, ttl=timedelta(hours=72))
    link.id = uuid4()

    assert link.token_hash == hash_passkey_reset_token(token)
    assert link.expires_at > datetime.now(UTC) + timedelta(hours=71, minutes=59)
    assert link.expires_at < datetime.now(UTC) + timedelta(hours=72, minutes=1)
    assert len(link.short_id) == 8
    assert link.remaining_hours == 72


def test_admin_passkey_add_link_duration_parser() -> None:
    assert _passkey_add_link_duration_hours(None) == 24
    assert _passkey_add_link_duration_hours("48") == 48

    with pytest.raises(ValueError, match="whole number"):
        _passkey_add_link_duration_hours("1.5")
    with pytest.raises(ValueError, match="between 1 and 720"):
        _passkey_add_link_duration_hours("0")
    with pytest.raises(ValueError, match="between 1 and 720"):
        _passkey_add_link_duration_hours("721")


def test_build_passkey_add_link_normalizes_base_url() -> None:
    assert build_passkey_add_link("https://example.com/", "abc123") == (
        "https://example.com/passkey-add/abc123"
    )
    assert build_passkey_add_link("https://example.com/", "abc123", identifier="link-1") == (
        "https://example.com/passkey-add/abc123#identifier=link-1"
    )


def test_build_passkey_add_link_requires_base_url() -> None:
    with pytest.raises(ValueError, match="Base URL is required"):
        build_passkey_add_link("   ", "abc123")


def test_issue_passkey_reset_commits_to_database() -> None:
    user = SimpleNamespace(id=uuid4())
    db = DummyDB()

    token, link = asyncio.run(issue_passkey_reset(db, user))

    assert token
    assert db.added == [link]
    assert link.user_id == user.id
    assert link.token_hash == hash_passkey_reset_token(token)
    assert db.commit_calls == 1
    assert db.refresh_calls == 1


def test_websocket_hub_connect_broadcast_disconnect() -> None:
    hub = WebSocketHub()
    list_id = uuid4()
    ws = DummyWebSocket()

    asyncio.run(hub.connect(list_id, ws))
    assert ws.accepted is True

    asyncio.run(hub.broadcast(list_id, {"type": "x"}))
    assert ws.events == [{"type": "x"}]

    hub.disconnect(list_id, ws)
    # cover no-op branch
    hub.disconnect(list_id, ws)


def test_websocket_hub_drops_slow_connections_without_blocking_peers() -> None:
    hub = WebSocketHub(send_timeout_seconds=0.001, close_timeout_seconds=0.001)
    list_id = uuid4()
    slow_ws = SlowDummyWebSocket()
    fast_ws = DummyWebSocket()

    asyncio.run(hub.connect(list_id, slow_ws))
    asyncio.run(hub.connect(list_id, fast_ws))

    asyncio.run(hub.broadcast(list_id, {"type": "x"}))
    assert slow_ws.send_calls == 1
    assert slow_ws.close_calls == 1
    assert fast_ws.events == [{"type": "x"}]

    asyncio.run(hub.broadcast(list_id, {"type": "y"}))
    assert slow_ws.send_calls == 1
    assert slow_ws.close_calls == 1
    assert fast_ws.events == [{"type": "x"}, {"type": "y"}]


def test_security_helpers_handle_long_passwords() -> None:
    long_password = "x" * 100
    password_hash = hash_password(long_password)
    assert verify_password(long_password, password_hash)


def test_auth_flow_session_validity_uses_short_ttl(monkeypatch) -> None:
    monkeypatch.setattr("app.api.v1.routes.auth.settings.auth_flow_expire_seconds", 60)

    fresh_session = _new_auth_flow_session(challenge="x")
    assert _auth_flow_session_is_valid(fresh_session) is True

    expired_session = {
        "issued_at": (datetime.now(UTC) - timedelta(seconds=61)).isoformat(),
    }
    assert _auth_flow_session_is_valid(expired_session) is False

    assert _auth_flow_session_is_valid({}) is False
    assert _auth_flow_session_is_valid({"issued_at": "not-a-date"}) is False
    assert _auth_flow_session_is_valid({"issued_at": "2026-04-03T12:00:00"}) is False


def test_auth_session_validity_checks_idle_and_absolute_windows(monkeypatch) -> None:
    now = datetime.now(UTC)
    monkeypatch.setattr("app.services.auth_sessions.settings.session_idle_timeout_seconds", 60)

    valid_session = SimpleNamespace(
        last_seen_at=now - timedelta(seconds=30),
        expires_at=now + timedelta(days=1),
    )
    assert _auth_session_is_valid(valid_session, now) is True

    idle_expired_session = SimpleNamespace(
        last_seen_at=now - timedelta(seconds=61),
        expires_at=now + timedelta(days=1),
    )
    assert _auth_session_is_valid(idle_expired_session, now) is False

    absolute_expired_session = SimpleNamespace(
        last_seen_at=now - timedelta(seconds=30),
        expires_at=now - timedelta(seconds=1),
    )
    assert _auth_session_is_valid(absolute_expired_session, now) is False


def test_auth_session_datetime_normalization_accepts_naive_values() -> None:
    naive = datetime(2026, 4, 3, 12, 0, 0)
    normalized = _as_utc(naive)
    assert normalized.tzinfo is UTC
    assert normalized.hour == 12


def test_revoke_auth_session_ignores_invalid_or_missing_session_ids() -> None:
    invalid_request = Request(
        {"type": "http", "headers": [], "session": {AUTH_SESSION_ID_KEY: "not-a-uuid"}}
    )
    invalid_db = DummyAuthSessionDB()
    asyncio.run(revoke_auth_session(invalid_request, invalid_db))
    assert invalid_db.commit_calls == 0

    missing_request = Request(
        {"type": "http", "headers": [], "session": {AUTH_SESSION_ID_KEY: str(uuid4())}}
    )
    missing_db = DummyAuthSessionDB(auth_session=None)
    asyncio.run(revoke_auth_session(missing_request, missing_db))
    assert missing_db.commit_calls == 0


def test_get_session_user_clears_invalid_server_session_ids() -> None:
    request = Request({"type": "http", "headers": [], "session": {AUTH_SESSION_ID_KEY: "bad-id"}})

    assert asyncio.run(get_session_user(request, DummyAuthSessionDB())) is None
    assert request.session == {}


def test_get_current_user_rejects_bearer_tokens_without_subject() -> None:
    from app.api.deps import get_current_user

    token = jwt.encode(
        {"exp": datetime.now(UTC) + timedelta(minutes=5)},
        settings.secret_key,
        algorithm=settings.algorithm,
    )
    request = Request({"type": "http", "headers": [], "session": {}})

    try:
        asyncio.run(get_current_user(request, DummyAuthSessionDB(), token))
    except HTTPException as exc:
        assert exc.status_code == 401
    else:  # pragma: no cover - defensive assertion
        raise AssertionError("Expected get_current_user to reject tokens without a subject")


def test_get_application_version_reads_version_file(tmp_path, monkeypatch) -> None:
    version_file = tmp_path / "VERSION"
    version_file.write_text("9.9.9\n", encoding="utf-8")
    monkeypatch.setattr("app.admin.VERSION_FILE", version_file)
    get_application_version.cache_clear()

    assert get_application_version() == "9.9.9"

    missing_version_file = tmp_path / "MISSING_VERSION"
    monkeypatch.setattr("app.admin.VERSION_FILE", missing_version_file)
    get_application_version.cache_clear()

    assert get_application_version() == "development"


def test_admin_auth_backend_redirects_and_allows(monkeypatch) -> None:
    auth = SessionAdminAuth()

    login_request = Request({"type": "http", "headers": [], "session": {}})
    login_response = asyncio.run(auth.login(login_request))
    assert login_response.headers["location"] == "/login"

    logout_request = Request({"type": "http", "headers": [], "session": {"access_token": "x"}})
    logout_response = asyncio.run(auth.logout(logout_request))
    assert logout_request.session == {}
    assert logout_response.headers["location"] == "/login"

    monkeypatch.setattr("app.admin.AsyncSessionLocal", lambda: DummySessionContext())

    anon_request = Request({"type": "http", "headers": [], "session": {}})

    async def _anon_user(request, session) -> None:
        return None

    monkeypatch.setattr("app.admin._get_session_user", _anon_user)
    anon_response = asyncio.run(auth.authenticate(anon_request))
    assert anon_response.headers["location"] == "/login"

    non_admin_request = Request({"type": "http", "headers": [], "session": {}})

    async def _non_admin_user(request, session) -> SimpleNamespace:
        return SimpleNamespace(is_admin=False)

    monkeypatch.setattr("app.admin._get_session_user", _non_admin_user)
    non_admin_response = asyncio.run(auth.authenticate(non_admin_request))
    assert non_admin_response.headers["location"] == "/"

    admin_request = Request({"type": "http", "headers": [], "session": {}})

    async def _admin_user(request, session) -> SimpleNamespace:
        return SimpleNamespace(is_admin=True)

    monkeypatch.setattr("app.admin._get_session_user", _admin_user)
    assert asyncio.run(auth.authenticate(admin_request)) is True


def test_bootstrap_admin_email_helper_respects_config(monkeypatch) -> None:
    db = DummyDB()
    user = SimpleNamespace(email="admin@example.com", is_admin=False)

    monkeypatch.setattr("app.api.v1.routes.auth.settings.bootstrap_admin_email", None)
    assert asyncio.run(_apply_bootstrap_admin_email(db, user)) is user
    assert db.commit_calls == 0

    monkeypatch.setattr(
        "app.api.v1.routes.auth.settings.bootstrap_admin_email", "other@example.com"
    )
    assert asyncio.run(_apply_bootstrap_admin_email(db, user)) is user
    assert db.commit_calls == 0

    monkeypatch.setattr(
        "app.api.v1.routes.auth.settings.bootstrap_admin_email", "admin@example.com"
    )
    user.is_admin = True
    assert asyncio.run(_apply_bootstrap_admin_email(db, user)) is user
    assert db.commit_calls == 0


def test_settings_normalize_blank_emails() -> None:
    assert Settings(bootstrap_admin_email="").bootstrap_admin_email is None
    assert Settings(bootstrap_admin_email="   ").bootstrap_admin_email is None
    assert Settings(privacy_email="").privacy_email is None
    assert Settings(privacy_email="   ").privacy_email is None
    assert Settings(support_email="").support_email is None
    assert Settings(support_email="   ").support_email is None
    assert str(Settings(bootstrap_admin_email="admin@example.com").bootstrap_admin_email) == (
        "admin@example.com"
    )
    assert str(Settings(privacy_email="privacy@example.com").privacy_email) == "privacy@example.com"
    assert str(Settings(support_email="support@example.com").support_email) == "support@example.com"


def test_required_email_startup_check_requires_contact() -> None:
    ensure_required_email_configured("privacy@example.com", "PRIVACY_EMAIL")

    with pytest.raises(RuntimeError, match="PRIVACY_EMAIL must be set"):
        ensure_required_email_configured(None, "PRIVACY_EMAIL")
    with pytest.raises(RuntimeError, match="SUPPORT_EMAIL must be set"):
        ensure_required_email_configured(None, "SUPPORT_EMAIL")


def test_load_settings_reports_invalid_json_env_value(monkeypatch) -> None:
    class ComplexSettings(BaseSettings):
        model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

        webcredentials_apps: list[str]

        @classmethod
        def settings_customise_sources(
            cls,
            settings_cls,
            init_settings,
            env_settings,
            dotenv_settings,
            file_secret_settings,
        ):
            return (
                init_settings,
                FriendlyEnvSettingsSource(settings_cls),
                dotenv_settings,
                file_secret_settings,
            )

    monkeypatch.setenv("WEBCREDENTIALS_APPS", "not-json")

    with pytest.raises(ConfigurationError) as exc_info:
        load_settings(ComplexSettings)

    assert str(exc_info.value) == (
        "Invalid application configuration. Invalid JSON in environment variable "
        '"webcredentials_apps" for settings field "webcredentials_apps". '
        "Expected JSON compatible with list[str]. Received 'not-json'."
    )


def test_load_settings_reports_validation_errors() -> None:
    class InvalidSettings(BaseSettings):
        required_count: int

    with pytest.raises(ConfigurationError) as exc_info:
        load_settings(InvalidSettings)

    assert str(exc_info.value) == (
        "Invalid application configuration. required_count: Field required"
    )


def test_config_error_helpers_cover_edge_cases() -> None:
    assert _format_invalid_env_value("x" * 200, limit=20) == "'xxxxxxxxxxxxxxxx..."
    assert _join_validation_path(()) == "<settings>"


def test_settings_normalize_app_base_url_and_webcredentials_apps() -> None:
    settings_obj = Settings(
        app_base_url=" https://planini.malaber.de/ ",
        webcredentials_apps="VWKG94374J.de.malaber.planini, VWKG94374J.de.malaber.planini.beta",
    )

    assert settings_obj.app_base_url == "https://planini.malaber.de"
    assert settings_obj.webcredentials_apps == [
        "VWKG94374J.de.malaber.planini",
        "VWKG94374J.de.malaber.planini.beta",
    ]


def test_settings_normalize_app_base_url_empty_none_and_invalid() -> None:
    assert Settings(app_base_url="   ").app_base_url is None
    assert Settings(webcredentials_apps=None).webcredentials_apps == []

    with pytest.raises(ValidationError):
        Settings(app_base_url="not-a-url")


def test_ui_test_bootstrap_allows_only_localhost_safe_settings() -> None:
    settings_obj = Settings(
        ui_test_bootstrap_enabled=True,
        app_base_url="http://127.0.0.1:8018",
        webauthn_rp_id="localhost",
        webcredentials_apps=[],
    )

    assert settings_obj.ui_test_bootstrap_enabled is True


def test_ui_test_bootstrap_rejects_non_localhost_auth_configuration() -> None:
    with pytest.raises(ValidationError) as exc_info:
        Settings(
            ui_test_bootstrap_enabled=True,
            app_base_url="https://planini.malaber.de",
            webauthn_rp_id="planini.malaber.de",
            webcredentials_apps=["VWKG94374J.de.malaber.planini"],
        )

    message = str(exc_info.value)
    assert "Refusing startup because UI_TEST_BOOTSTRAP_ENABLED may only be used" in message
    assert "APP_BASE_URL='https://planini.malaber.de' must point to localhost" in message
    assert "WEBAUTHN_RP_ID must be 'localhost'" in message
    assert "WEBCREDENTIALS_APPS must be empty" in message


def test_load_settings_rejects_ui_test_bootstrap_with_production_env(monkeypatch) -> None:
    monkeypatch.setenv("UI_TEST_BOOTSTRAP_ENABLED", "true")
    monkeypatch.setenv("APP_BASE_URL", "https://planini.malaber.de")
    monkeypatch.setenv("WEBAUTHN_RP_ID", "planini.malaber.de")
    monkeypatch.setenv("WEBCREDENTIALS_APPS", '["VWKG94374J.de.malaber.planini"]')

    with pytest.raises(ConfigurationError) as exc_info:
        load_settings(Settings)

    message = str(exc_info.value)
    assert "Refusing startup because UI_TEST_BOOTSTRAP_ENABLED may only be used" in message
    assert "APP_BASE_URL='https://planini.malaber.de' must point to localhost" in message


def test_passkey_request_helpers() -> None:
    request = Request(
        {
            "type": "http",
            "scheme": "http",
            "path": "/login",
            "server": ("localhost", 8000),
            "headers": [(b"host", b"localhost:8000")],
        }
    )

    assert _rp_id_for_request(request) == "localhost"
    assert _origin_for_request(request) == "http://localhost:8000"
    assert _password_auth_disabled().status_code == 400

    hostless_request = Request({"type": "http", "scheme": "http", "path": "/", "headers": []})
    assert _password_auth_disabled().detail.startswith("Password-based auth is disabled")
    try:
        _rp_id_for_request(hostless_request)
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 400
    else:  # pragma: no cover
        raise AssertionError("Expected hostless passkey request to fail")


def test_passkey_request_helper_prefers_configured_rp_id(monkeypatch) -> None:
    request = Request(
        {
            "type": "http",
            "scheme": "https",
            "path": "/login",
            "server": ("pr-42.review.example.com", 443),
            "headers": [(b"host", b"pr-42.review.example.com")],
        }
    )

    monkeypatch.setattr("app.api.v1.routes.auth.settings.webauthn_rp_id", "review.example.com")
    assert _rp_id_for_request(request) == "review.example.com"


def test_passkey_request_helpers_prefer_configured_app_base_url(monkeypatch) -> None:
    request = Request(
        {
            "type": "http",
            "scheme": "http",
            "path": "/login",
            "server": ("localhost", 8000),
            "headers": [(b"host", b"localhost:8000")],
        }
    )

    monkeypatch.setattr("app.api.v1.routes.auth.settings.webauthn_rp_id", None)
    monkeypatch.setattr(
        "app.api.v1.routes.auth.settings.app_base_url",
        "https://planini.malaber.de",
    )

    assert _rp_id_for_request(request) == "planini.malaber.de"
    assert _origin_for_request(request) == "https://planini.malaber.de"


def test_sqlite_database_path_helper_handles_sqlite_and_non_sqlite_urls(tmp_path) -> None:
    relative_path = _sqlite_database_path("sqlite+aiosqlite:///./var/test.db")

    assert relative_path == Path.cwd() / "var" / "test.db"
    assert _sqlite_database_path("sqlite:///:memory:") is None
    assert _sqlite_database_path("postgresql+asyncpg://user:pass@db/app") is None


def test_database_path_writable_allows_non_sqlite_urls() -> None:
    ensure_database_path_writable("postgresql+asyncpg://user:pass@db/app")


def test_database_path_writable_allows_existing_sqlite_file(monkeypatch, tmp_path) -> None:
    db_path = tmp_path / "app.db"
    db_path.write_text("", encoding="utf-8")

    monkeypatch.setattr("app.core.startup_checks.os.access", lambda path, mode: path == db_path)

    ensure_database_path_writable(f"sqlite+aiosqlite:///{db_path}")


def test_database_path_writable_rejects_unwritable_sqlite_file(monkeypatch, tmp_path) -> None:
    db_path = tmp_path / "app.db"
    db_path.write_text("", encoding="utf-8")

    monkeypatch.setattr("app.core.startup_checks.os.access", lambda path, mode: False)

    with pytest.raises(RuntimeError, match="SQLite database file"):
        ensure_database_path_writable(f"sqlite+aiosqlite:///{db_path}")


def test_database_path_writable_rejects_missing_parent_directory(tmp_path) -> None:
    db_path = tmp_path / "missing" / "app.db"

    with pytest.raises(RuntimeError, match="does not exist"):
        ensure_database_path_writable(f"sqlite+aiosqlite:///{db_path}")


def test_database_path_writable_rejects_unwritable_parent_directory(monkeypatch, tmp_path) -> None:
    db_path = tmp_path / "app.db"

    monkeypatch.setattr("app.core.startup_checks.os.access", lambda path, mode: False)

    with pytest.raises(RuntimeError, match="SQLite database directory"):
        ensure_database_path_writable(f"sqlite+aiosqlite:///{db_path}")


def test_database_path_writable_allows_writable_parent_directory(monkeypatch, tmp_path) -> None:
    db_path = tmp_path / "app.db"

    monkeypatch.setattr("app.core.startup_checks.os.access", lambda path, mode: path == tmp_path)

    ensure_database_path_writable(f"sqlite+aiosqlite:///{db_path}")


def test_startup_checks_main_uses_configured_database_url(monkeypatch) -> None:
    monkeypatch.setattr("app.core.startup_checks.settings.database_url", "sqlite:///./app.db")
    seen: list[str] = []

    def _capture(database_url: str) -> None:
        seen.append(database_url)

    monkeypatch.setattr("app.core.startup_checks.ensure_database_path_writable", _capture)

    assert startup_checks.main() == 0
    assert seen == ["sqlite:///./app.db"]
