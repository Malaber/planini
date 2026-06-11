import os
from pathlib import Path

from sqlalchemy.engine import make_url

from app.core.config import settings


def ensure_privacy_email_configured(privacy_email: object | None) -> None:
    if privacy_email is not None:
        return
    raise RuntimeError(
        "PRIVACY_EMAIL must be set to a valid contact email before Planini can start."
    )


def _sqlite_database_path(database_url: str) -> Path | None:
    url = make_url(database_url)
    if url.get_backend_name() != "sqlite":
        return None
    database = url.database
    if database in {None, "", ":memory:"}:
        return None
    path = Path(database)
    if not path.is_absolute():
        path = Path.cwd() / path
    return path


def ensure_database_path_writable(database_url: str) -> None:
    path = _sqlite_database_path(database_url)
    if path is None:
        return

    if path.exists():
        if os.access(path, os.W_OK):
            return
        raise RuntimeError(
            "SQLite database file "
            f"'{path}' is not writable for uid={os.getuid()} gid={os.getgid()}. "
            "Make the mounted file writable by the container user."
        )

    parent = path.parent
    if not parent.exists():
        raise RuntimeError(
            "SQLite database directory " f"'{parent}' does not exist for database '{path}'."
        )
    if os.access(parent, os.W_OK | os.X_OK):
        return
    raise RuntimeError(
        "SQLite database directory "
        f"'{parent}' is not writable for uid={os.getuid()} gid={os.getgid()}. "
        "Make the mounted directory writable by the container user."
    )


def main() -> int:
    ensure_privacy_email_configured(settings.privacy_email)
    ensure_database_path_writable(settings.database_url)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
