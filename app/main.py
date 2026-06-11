import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app.i18n import LOCALE_COOKIE_NAME, resolve_locale
from app.admin import configure_admin
from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import run_migrations
from app.core.startup_checks import ensure_privacy_email_configured
from app.services.backup_scheduler import start_backup_scheduler, stop_backup_scheduler
from app.services.fixture_seed import ensure_seed_data
from app.web.routes import router as web_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    backup_scheduler = None
    try:
        ensure_privacy_email_configured(settings.privacy_email)
        logger.info("Running database migrations")
        await run_migrations()
        logger.info("Database migrations completed")
        if settings.seed_data_path:
            logger.info("Seeding startup fixture from %s", settings.seed_data_path)
            from app.core.database import AsyncSessionLocal

            async with AsyncSessionLocal() as session:
                await ensure_seed_data(session, settings.seed_data_path)
            logger.info("Startup fixture seeding completed")
        backup_scheduler = start_backup_scheduler()
    except Exception:
        logger.exception("Application startup failed")
        raise
    try:
        yield
    finally:
        await stop_backup_scheduler(backup_scheduler)


app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.secret_key,
    https_only=settings.secure_cookies,
    max_age=settings.session_max_age_seconds,
)
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")
app.include_router(api_router, prefix="/api/v1")
app.include_router(web_router)
app.mount("/static", StaticFiles(directory="app/web/static"), name="static")
configure_admin(app)


@app.middleware("http")
async def add_locale_to_request(request: Request, call_next):
    locale = resolve_locale(request)
    request.state.locale = locale
    response = await call_next(request)
    if request.query_params.get("lang") == locale:
        response.set_cookie(
            key=LOCALE_COOKIE_NAME,
            value=locale,
            max_age=settings.session_max_age_seconds,
            httponly=False,
            samesite="lax",
            secure=settings.secure_cookies,
        )
    return response


@app.get("/health")
async def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/api")
async def api_root() -> JSONResponse:
    return JSONResponse({"name": settings.app_name, "version": "v1", "base": "/api/v1"})
