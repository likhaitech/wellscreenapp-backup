from fastapi import APIRouter, Body, Depends, HTTPException, status
from pydantic import ValidationError

from app.models.system_settings import SystemPatchRequest, SystemSettingsUpdate
from app.services.admin_auth_service import require_admin
from app.services.server_info import server_info
from app.services.system_log_service import create_system_log
from app.services.system_settings_service import (
    get_system_settings,
    update_system_settings,
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
    """Validate and apply a system configuration patch.

    A rejected patch changes nothing and is recorded as a warning log.
    """
    actor = current_admin.get("uid")

    try:
        patch = SystemPatchRequest.model_validate(payload)
    except ValidationError as exc:
        errors = [
            f"{'.'.join(str(p) for p in err['loc']) or 'patch'}: {err['msg']}"
            for err in exc.errors()
        ]
        create_system_log(
            level="warning",
            action="system_patch_rejected",
            message="System patch failed validation; no changes applied",
            actor_uid=actor,
            details={"errors": errors},
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"message": "Patch rejected", "errors": errors},
        )

    changes = patch.settings.model_dump(exclude_none=True)

    if not changes:
        create_system_log(
            level="warning",
            action="system_patch_rejected",
            message="System patch contained no settings; no changes applied",
            actor_uid=actor,
            details={"errors": ["settings: no changes provided"]},
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "message": "Patch rejected",
                "errors": ["settings: no changes provided"],
            },
        )

    if patch.validate_only:
        return {"valid": True, "applied": False, "changes": changes}

    try:
        updated = update_system_settings(changes, updated_by=actor or "unknown")
        create_system_log(
            level="info",
            action="system_patch_applied",
            message=f"System patch {patch.version or '(unversioned)'} applied",
            actor_uid=actor,
            details={
                "version": patch.version,
                "description": patch.description,
                "changes": changes,
            },
        )
        return {
            "valid": True,
            "applied": True,
            "changes": changes,
            "settings": updated,
        }
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
