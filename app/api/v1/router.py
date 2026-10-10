from fastapi import APIRouter, Depends

from app.api.deps import require_admin_user, require_non_admin_user
from app.api.v1.routes import (
    auth,
    backups,
    categories,
    households,
    items,
    lists,
    public_list_links,
    public_lists,
    ws_lists,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(households.router, dependencies=[Depends(require_non_admin_user)])
api_router.include_router(lists.router, dependencies=[Depends(require_non_admin_user)])
api_router.include_router(public_list_links.router, dependencies=[Depends(require_non_admin_user)])
api_router.include_router(public_lists.router)
api_router.include_router(items.router, dependencies=[Depends(require_non_admin_user)])
api_router.include_router(ws_lists.router)
api_router.include_router(categories.router, dependencies=[Depends(require_admin_user)])
api_router.include_router(backups.router)
