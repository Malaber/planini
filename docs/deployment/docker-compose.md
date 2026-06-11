# Docker Compose deployment

The published container is intended to run behind Docker Compose. For a low-traffic self-hosted deployment, SQLite is enough and keeps local and deployed behavior aligned.

## Runtime characteristics

- image example: `ghcr.io/malaber/planini:0.1.2`
- multi-architecture image for `linux/amd64` and `linux/arm64`
- app port inside the container: `8000`
- health endpoint: `/health`
- database migrations run automatically on startup
- SQLite database path inside the container: `/data/planini.db`
- persisted SQLite file on the host: `./data/planini.db`
- backup dump path inside the container: `/backups`
- persisted backup files on the host: `./backups`

## Example `.env`

```dotenv
PLANINI_IMAGE=ghcr.io/malaber/planini:0.1.2
SECRET_KEY=replace-this-with-a-long-random-secret
PRIVACY_EMAIL=privacy@example.com
SUPPORT_EMAIL=support@example.com
APP_BASE_URL=https://planini.example.com
WEBAUTHN_RP_ID=planini.example.com
WEBCREDENTIALS_APPS=["VWKG94374J.de.malaber.planini"]
SECURE_COOKIES=true
UVICORN_FORWARDED_ALLOW_IPS=127.0.0.1
BOOTSTRAP_ADMIN_EMAIL=admin@example.com
BACKUP_DIRECTORY=/backups
BACKUP_SLOTS=["slot-1@01:00"]
```

## Example `docker-compose.yml`

```yaml
services:
  app:
    image: ${PLANINI_IMAGE}
    restart: unless-stopped
    environment:
      SECRET_KEY: ${SECRET_KEY}
      PRIVACY_EMAIL: ${PRIVACY_EMAIL}
      SUPPORT_EMAIL: ${SUPPORT_EMAIL}
      DATABASE_URL: sqlite+aiosqlite:////data/planini.db
      BACKUP_DIRECTORY: ${BACKUP_DIRECTORY}
      BACKUP_SLOTS: ${BACKUP_SLOTS}
      APP_BASE_URL: ${APP_BASE_URL}
      WEBAUTHN_RP_ID: ${WEBAUTHN_RP_ID}
      WEBCREDENTIALS_APPS: ${WEBCREDENTIALS_APPS}
      SECURE_COOKIES: ${SECURE_COOKIES}
      BOOTSTRAP_ADMIN_EMAIL: ${BOOTSTRAP_ADMIN_EMAIL}
      UVICORN_FORWARDED_ALLOW_IPS: ${UVICORN_FORWARDED_ALLOW_IPS}
    ports:
      - "8000:8000"
    volumes:
      - ./data:/data
      - ./backups:/backups
    healthcheck:
      test: ["CMD", "python", "-c", "from urllib.request import urlopen; urlopen('http://127.0.0.1:8000/health')"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
```

## Deploy

```bash
mkdir -p data backups
sudo chown -R 100:101 data backups
docker compose pull
docker compose up -d
```

Then open `http://YOUR_HOST:8000/health` to confirm the container is healthy.

## Generate a passkey recovery link

If an account owner or admin loses their passkey, you can generate a one-time add-passkey link from the running container:

```bash
docker compose exec app python scripts/create_passkey_reset_link.py \
  --email admin@example.com \
  --base-url https://planini.example.com
```

If you prefer to target a user by ID instead of email:

```bash
docker compose exec app python scripts/create_passkey_reset_link.py \
  --user-id 00000000-0000-0000-0000-000000000000 \
  --base-url https://planini.example.com
```

Notes:

- `--base-url` should match the public HTTPS URL people use in the browser, not the internal container address.
- The script reads `DATABASE_URL` from the container environment by default, so you usually do not need to pass `--database-url` when using `docker compose exec`.
- The printed `/passkey-add/...` URL is single-use and expires automatically.

## Production notes

- set a strong `SECRET_KEY`
- set `PRIVACY_EMAIL` to a monitored contact address; Planini refuses startup without it
- set `SUPPORT_EMAIL` to a monitored support address; Planini refuses startup without it
- keep `SECURE_COOKIES=true` when serving over HTTPS
- put the app behind a reverse proxy or load balancer that terminates TLS
- set `APP_BASE_URL` to the public HTTPS origin users and passkey clients reach
- set `WEBAUTHN_RP_ID` to that public hostname
- set `WEBCREDENTIALS_APPS` to a JSON array of Apple app IDs allowed to use native passkeys
- make the mounted data directory writable by the container user before first start, for example `sudo chown -R 100:101 data`
- make the mounted backup directory writable too, for example `sudo chown -R 100:101 backups`
- set `BACKUP_SLOTS` to a JSON array like `["slot-1@01:00"]` for rotating automatic slot backups
- verify `https://YOUR_HOST/.well-known/apple-app-site-association` returns the expected `webcredentials.apps` payload
- set `UVICORN_FORWARDED_ALLOW_IPS` to the IP or CIDR of your trusted proxy network
- keep `./data` on persistent storage so `./data/planini.db` survives container replacement
- to upgrade, change `PLANINI_IMAGE` and run `docker compose pull && docker compose up -d`
