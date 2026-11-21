import os

from fastapi import APIRouter, Body, Depends, HTTPException, status

from app.models.system_settings import SystemSettingsUpdate
from app.services.admin_auth_service import require_admin
from app.services.server_info import server_info
from app.services.system_patch_service import PatchRejected, apply_patch
from app.services.system_log_service import create_system_log
from app.services.system_settings_service import (
    get_system_settings,
    update_system_settings,
)

def _require_patch_api() -> None:
    """System settings change only through the backend patch tool unless a
    developer turns the HTTP routes on (SYSTEM_PATCH_API_ENABLED=true)."""
    if os.getenv("SYSTEM_PATCH_API_ENABLED", "").strip().lower() != "true":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="System patches are applied through the backend, not the app.",
        )


router = APIRouter(
    prefix="/admin/settings",
    tags=["Admin Settings"],
)


@router.get("/")
def read_system_settings(
    current_admin: dict = Depends(require_admin),
):
    try:
        return {**get_system_settings(), "server": server_info()}

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.patch("/")
def edit_system_settings(
    request: SystemSettingsUpdate,
    current_admin: dict = Depends(require_admin),
):
    _require_patch_api()
    changes = request.model_dump(exclude_none=True)

    try:
        updated_settings = update_system_settings(
            changes,
            updated_by=current_admin.get("uid", "unknown"),
        )

        create_system_log(
            level="info",
            action="system_settings_updated",
            message="Admin updated system settings",
            actor_uid=current_admin.get("uid"),
            details={
                "changes": changes,
            },
        )

        return updated_settings

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.post("/patch")
def apply_system_patch(
    payload: dict = Body(...),
    current_admin: dict = Depends(require_admin),
):
    """Validate and apply a system configuration patch over HTTP.

    Off by default: patches are applied on the backend with
    scripts/apply_system_patch.py, never from the app. Developers can turn
    this route on for maintenance with SYSTEM_PATCH_API_ENABLED=true.
    """
    _require_patch_api()
    try:
        return apply_patch(
            payload,
            actor=current_admin.get("uid"),
            update=update_system_settings,
            log=create_system_log,
        )
    except PatchRejected as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"message": "Patch rejected", "errors": exc.errors},
        ) from None
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
