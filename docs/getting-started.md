# Getting started

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
cp .env.example .env
uvicorn app.main:app --reload
```

Set `PRIVACY_EMAIL` and `SUPPORT_EMAIL` in `.env` to monitored contact addresses. Planini
refuses startup without either one.

Open `http://localhost:8000/docs`.

## Environment bootstrap

Use the repo setup script rather than ad-hoc install commands:

```bash
./scripts/setup_env.sh
```

For Codex environments, use `.codex/setup.sh`.

### Network allowlist for dependency installs

If the environment is egress-restricted, allow outbound HTTPS to at least:

- `pypi.org`
- `files.pythonhosted.org`

Add any internal package registry domains your organization uses.

## Database migrations

Run migrations locally with:

```bash
alembic upgrade head
```

The `alembic/` directory contains the migration tooling and revision history:

- `alembic/env.py` wires Alembic to SQLAlchemy metadata
- `alembic/versions/` stores the versioned migration scripts

## API and UI entrypoints

- API docs: `http://localhost:8000/docs`
- Browser UI: `http://localhost:8000/login`
