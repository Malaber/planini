import json
from collections.abc import Iterable
from urllib.parse import urlparse

from pydantic import EmailStr, ValidationError, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict, SettingsError
from pydantic_settings.sources import EnvSettingsSource


class ConfigurationError(RuntimeError):
    """Raised when application settings cannot be loaded cleanly."""


def _format_invalid_env_value(value: object, *, limit: int = 160) -> str:
    rendered = repr(value)
    if len(rendered) <= limit:
        return rendered
    return f"{rendered[: limit - 3]}..."


def _join_validation_path(parts: Iterable[object]) -> str:
    return ".".join(str(part) for part in parts) or "<settings>"


class FriendlyEnvSettingsSource(EnvSettingsSource):
    def prepare_field_value(self, field_name, field, value, value_is_complex):
        try:
            return super().prepare_field_value(field_name, field, value, value_is_complex)
        except json.JSONDecodeError as exc:
            env_name = self._extract_field_info(field, field_name)[0][1]
            raise ValueError(
                f'Invalid JSON in environment variable "{env_name}" for settings field '
                f'"{field_name}". Expected JSON compatible with {field.annotation!r}. '
                f"Received {_format_invalid_env_value(value)}."
            ) from exc


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Planini"
    secret_key: str = "change-me"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 28
    session_max_age_seconds: int = 60 * 60 * 24 * 180
    session_idle_timeout_seconds: int = 60 * 60 * 24 * 28
    auth_flow_expire_seconds: int = 10 * 60
    database_url: str = "sqlite+aiosqlite:///./planini.db"
    app_base_url: str | None = None
    secure_cookies: bool = False
    webauthn_rp_id: str | None = None
    webcredentials_apps: list[str] = []
    seed_data_path: str | None = None
    bootstrap_admin_email: EmailStr | None = None
    privacy_email: EmailStr | None = None
    support_email: EmailStr | None = None
    ui_test_bootstrap_enabled: bool = False
    backup_directory: str | None = None
    backup_slots: list[str] = []
    pg_dump_command: str = "pg_dump"
    pg_restore_command: str = "pg_restore"

    @field_validator("app_base_url", mode="before")
    @classmethod
    def normalize_app_base_url(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        normalized = value.strip().rstrip("/")
        if not normalized:
            return None
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ValueError("app_base_url must be a valid http or https URL")
        return normalized

    @field_validator("webcredentials_apps", mode="before")
    @classmethod
    def normalize_webcredentials_apps(cls, value: object) -> object:
        if value is None:
            return []
        if isinstance(value, str):
            return [entry.strip() for entry in value.split(",") if entry.strip()]
        return value

    @field_validator("bootstrap_admin_email", "privacy_email", "support_email", mode="before")
    @classmethod
    def normalize_blank_email(cls, value: object) -> object:
        if isinstance(value, str) and value.strip() == "":
            return None
        return value

    @model_validator(mode="after")
    def validate_ui_test_bootstrap_safety(self) -> "Settings":
        if self.ui_test_bootstrap_enabled is False:
            return self

        failures: list[str] = []
        if self.app_base_url and _url_uses_non_localhost_host(self.app_base_url):
            failures.append(
                f"APP_BASE_URL={self.app_base_url!r} must point to localhost or a loopback host"
            )
        if self.webauthn_rp_id and self.webauthn_rp_id != "localhost":
            failures.append("WEBAUTHN_RP_ID must be 'localhost'")
        if self.webcredentials_apps:
            failures.append("WEBCREDENTIALS_APPS must be empty")

        if failures:
            details = "; ".join(failures)
            raise ValueError(
                "Refusing startup because UI_TEST_BOOTSTRAP_ENABLED may only be used with "
                f"localhost-only auth settings. {details}."
            )

        return self

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


def load_settings(settings_class: type[BaseSettings]) -> BaseSettings:
    try:
        return settings_class()
    except ValidationError as exc:
        details = "; ".join(
            f"{_join_validation_path(error['loc'])}: {error['msg']}" for error in exc.errors()
        )
        raise ConfigurationError(f"Invalid application configuration. {details}") from None
    except SettingsError as exc:
        detail = str(exc.__cause__ or exc)
        raise ConfigurationError(f"Invalid application configuration. {detail}") from None


def build_settings() -> Settings:
    return load_settings(Settings)


def _url_uses_non_localhost_host(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.hostname not in {"localhost", "127.0.0.1", "::1"}


settings = build_settings()
