# Planini

Planini is a self-hostable grocery-list backend and fallback browser UI built with FastAPI.

## Highlights

- `/api/v1` REST API with OpenAPI docs
- passkey-first auth plus browser fallback UI
- households, lists, categories, and item CRUD
- live list updates over WebSocket
- Alembic migrations and SQLAlchemy 2 async ORM
- Docker images published to GHCR
- CI coverage gate at 100%

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --reload
```

Open [http://localhost:8000/docs](http://localhost:8000/docs).

For local development and verification, install dependencies in the repo `.venv` and run the
shared Invoke tasks from that environment. If `.codex/setup.sh` cannot use the host Python, keep
using `.venv/bin/...` commands rather than stopping.

## Documentation

- [Documentation index](docs/README.md)
- [Getting started](docs/getting-started.md)
- [Testing and browser e2e](docs/testing.md)
- [App Store screenshot download and upload guide](docs/app-store-screenshots.md)
- [Deployment overview](docs/deployment/README.md)
- [Docker Compose deployment](docs/deployment/docker-compose.md)
- [Webhooker deployment](docs/deployment/webhooker.md)
- [iOS starter app](ios/PlaniniIOS/README.md)

## App Store screenshots

Every release from `main` attaches a ready-to-upload iPhone, iPad, and Apple Watch screenshot ZIP
for English and German. Download it from the
[latest GitHub Release](https://github.com/Malaber/planini/releases/latest), then follow the
[App Store screenshot guide](docs/app-store-screenshots.md).

## Native iOS passkey deployments

The native iOS app now uses a build-time backend URL instead of an in-app server switcher. That keeps the signed bundle identifier, Associated Domains entitlement, and backend WebAuthn relying party aligned for Apple passkeys.

For an iOS build that should sign in with passkeys:

1. Stamp the app with the final backend URL and bundle identifier:
   ```bash
   .venv/bin/inv configure-ios-app \
     --backend-url=https://shopping.example.com \
     --bundle-id=com.example.shopping
   ```
2. Sign the app with the Apple Developer team that will ship it.
3. Deploy the backend on that same host with `WEBAUTHN_RP_ID=shopping.example.com`.
4. Configure `APP_BASE_URL=https://shopping.example.com` and `WEBCREDENTIALS_APPS=ABCD123456.com.example.shopping` so the backend can serve `/.well-known/apple-app-site-association` itself.

Apple's native passkey flow only works when those values match. Self-hosters can use the same Invoke flow to build their own signed app variant for their own domain.

## Release naming

GitHub Releases created from `main` use merged PR metadata for their title.
Add a `Release title:` line to the PR description to set an explicit release name.
If that line is blank or omitted, the workflow uses the PR title instead.
The workflow prefixes the final release title with the version automatically, so the PR field should
contain only the human-readable title.

## Seeded review identities

The checked-in review fixture (`app/fixtures/review_seed.json`) includes deterministic preview users:

- `planini@schaedler.rocks` (non-admin): seeded into all households (owner/member as appropriate)
- `planini_admin@schaedler.rocks` (admin): instance-admin only; household memberships are stripped
- `preview@example.com` and `preview-invitee@example.com` are kept for compatibility

The browser e2e flow uses a separate fixture, `app/fixtures/review_seed_e2e.json`, so the review deployment seed does not need to carry browser-private authenticator material.

## Export passkeys from a running PR instance

Use the helper script to copy passkey material from a live preview database into seed fixtures:

```bash
DATABASE_URL='sqlite:///path/to/preview.db' python scripts/export_seed_passkeys.py
```

Optional flags:

- `--email <address>` (repeatable) to limit exported users
- `--database-url <url>` to override `DATABASE_URL`

The script prints JSON containing each selected user's passkey `credential_id`, `public_key_b64`, and `sign_count`.

## Install local dependencies

Use the shared Invoke bootstrap task to install local development dependencies:

```bash
python3.14 -m venv .venv
.venv/bin/pip install invoke
.venv/bin/inv install-deps
```

Optional flags:

- `--python-bin <python>` to choose a different Python executable for the virtualenv
- `--with-browser` to also install the Playwright Chromium bundle
- `--browser-with-deps` to use Playwright's `--with-deps` install flow when `--with-browser` is enabled

## Generate a passkey recovery link from the server

If someone loses their passkey, you can generate the same one-time add-passkey link that the admin UI creates directly from inside the Docker container:

```bash
DATABASE_URL='sqlite+aiosqlite:///./planini.db' \
APP_BASE_URL='https://planini.example.com' \
python scripts/create_passkey_reset_link.py --email admin@example.com
```

Optional flags:

- `--user-id <uuid>` to target a user by UUID instead of email
- `--database-url <url>` to override `DATABASE_URL`
- `--base-url <url>` to override `APP_BASE_URL`

The script prints the one-time `/passkey-add/...` URL and its expiry timestamp.

For Docker Compose deployments, you can run it directly in the live container:

```bash
docker compose exec app python scripts/create_passkey_reset_link.py \
  --email admin@example.com \
  --base-url https://planini.example.com
```

## Python version

This project is configured for Python 3.14 in Docker and CI.

