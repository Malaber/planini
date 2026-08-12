#!/usr/bin/env python3
"""Export passkey material for selected users as JSON fixture data."""

from __future__ import annotations

import argparse
import base64
import json
import os
from typing import Any

from sqlalchemy import bindparam, create_engine, text

DEFAULT_EMAILS = (
    "planini_admin@schaedler.rocks",
    "planini@schaedler.rocks",
)


def _b64(value: bytes | None) -> str | None:
    if value is None:
        return None
    return base64.b64encode(value).decode("ascii")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Read passkey material from the configured database and print JSON output "
            "that can be copied into seed data."
        )
    )
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL"),
        help="Database URL. Defaults to DATABASE_URL environment variable.",
    )
    parser.add_argument(
        "--email",
        action="append",
        dest="emails",
        help="Email to export. Can be provided multiple times.",
    )
    args = parser.parse_args()

    database_url = args.database_url
    if not database_url:
        raise SystemExit("Missing --database-url (or DATABASE_URL).")

    emails = tuple(args.emails) if args.emails else DEFAULT_EMAILS
    query = text("""
        SELECT
          u.email,
          p.credential_id,
          p.public_key,
          p.sign_count,
          p.name
        FROM users AS u
        JOIN passkeys AS p ON p.user_id = u.id
        WHERE u.email IN :emails
        ORDER BY u.email ASC, p.created_at ASC
        """).bindparams(bindparam("emails", expanding=True))

    engine = create_engine(database_url)
    with engine.connect() as conn:
        rows = conn.execute(query, {"emails": emails}).mappings().all()

    payload: dict[str, dict[str, Any]] = {}
    for row in rows:
        user = payload.setdefault(row["email"], {"passkeys": []})
        user["passkeys"].append(
            {
                "name": row["name"],
                "credential_id": row["credential_id"],
                "public_key_b64": _b64(row["public_key"]),
                "sign_count": row["sign_count"],
            }
        )

    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
