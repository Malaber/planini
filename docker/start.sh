#!/bin/sh
set -eu

python -m app.core.startup_checks
python -c "from app.core.database import run_migrations_sync; run_migrations_sync()"

exec python -m uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --proxy-headers \
  --forwarded-allow-ips="${UVICORN_FORWARDED_ALLOW_IPS:-127.0.0.1}"
