"""System patches: validated, applied and logged on the backend only.

A system patch changes system-wide settings (minimum app version,
maintenance notice). It is applied by the developers with the backend tool
(scripts/apply_system_patch.py), never from the mobile app. The admin app
only shows the result: the current settings and the patch history in
System logs.

Every patch is validated first. A rejected patch changes nothing and is
recorded as a warning; an applied patch is recorded as info.
"""
from __future__ import annotations

from typing import Any, Callable

from pydantic import ValidationError

from app.models.system_settings import SystemPatchRequest
from app.services.system_log_service import create_system_log
from app.services.system_settings_service import update_system_settings


class PatchRejected(Exception):
    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


def apply_patch(
    payload: Any,
    *,
    actor: str | None,
    validate_only: bool | None = None,
    update: Callable[..., dict[str, Any]] = update_system_settings,
    log: Callable[..., None] = create_system_log,
) -> dict[str, Any]:
    """Validate and (unless validate_only) apply a patch. Raises PatchRejected."""
    try:
        patch = SystemPatchRequest.model_validate(payload)
    except ValidationError as exc:
        errors = [
            f"{'.'.join(str(p) for p in err['loc']) or 'patch'}: {err['msg']}"
            for err in exc.errors()
        ]
        log(
            level="warning",
            action="system_patch_rejected",
            message="System patch failed validation; no changes applied",
            actor_uid=actor,
            details={"errors": errors},
        )
        raise PatchRejected(errors) from None

    changes = patch.settings.model_dump(exclude_none=True)
    if not changes:
        errors = ["settings: no changes provided"]
        log(
            level="warning",
            action="system_patch_rejected",
            message="System patch contained no settings; no changes applied",
            actor_uid=actor,
            details={"errors": errors},
        )
        raise PatchRejected(errors)

    check_only = patch.validate_only if validate_only is None else validate_only
    if check_only:
        return {"valid": True, "applied": False, "changes": changes}

    updated = update(changes, updated_by=actor or "backend")
    log(
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
    return {"valid": True, "applied": True, "changes": changes, "settings": updated}
