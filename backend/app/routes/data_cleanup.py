"""Private, token-authenticated entry point for the scheduled retention job."""
from __future__ import annotations

import logging
import os
import secrets
from threading import Lock
from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException, Response

from ..services.data_cleanup_service import cleanup_old_data
from ..services.system_activity_service import record_job


router = APIRouter(prefix="/internal/maintenance", tags=["Internal maintenance"])
_logger = logging.getLogger(__name__)
_cleanup_lock = Lock()


@router.post("/cleanup", include_in_schema=False)
def run_scheduled_cleanup(
    response: Response,
    cleanup_token: Annotated[
        str | None, Header(alias="X-WellScreen-Cleanup-Token")
    ] = None,
) -> dict[str, Any]:
    # Never accept a project, retention period, or deletion mode from a caller.
    # Only server-side environment configuration controls those settings.
    expected_token = os.getenv("WELLSCREEN_CLEANUP_TOKEN", "")
    project_id = os.getenv("WELLSCREEN_CLEANUP_PROJECT_ID", "").strip()
    apply_setting = os.getenv("WELLSCREEN_CLEANUP_APPLY", "false")

    if len(expected_token) < 32 or not project_id or apply_setting not in (
        "true", "false"
    ):
        raise HTTPException(status_code=503, detail="Cleanup is not configured")

    if not cleanup_token or not secrets.compare_digest(
        cleanup_token.encode("utf-8"), expected_token.encode("utf-8")
    ):
        raise HTTPException(status_code=401, detail="Unauthorized")

    # The service also verifies the actual Firestore project before any writes.
    # Do not let a misconfigured emulator masquerade as the live database.
    if os.getenv("FIRESTORE_EMULATOR_HOST") and not project_id.startswith("demo-"):
        raise HTTPException(status_code=503, detail="Cleanup is not configured")

    if not _cleanup_lock.acquire(blocking=False):
        raise HTTPException(status_code=409, detail="Cleanup is already running")

    try:
        report = cleanup_old_data(
            dry_run=(apply_setting != "true"),
            expected_project=project_id,
        )
    except Exception as exc:
        # Do not expose credentials, database internals, or user history.
        _logger.error("Scheduled cleanup failed: %s", type(exc).__name__)
        record_job("data_cleanup", ok=False, summary={"error": type(exc).__name__},
                   log_entry=True, message="Data cleanup failed")
        raise HTTPException(status_code=500, detail="Cleanup failed") from None
    finally:
        _cleanup_lock.release()

    removed = report.get("removed") if isinstance(report, dict) else None
    total = sum(v for v in (removed or {}).values() if isinstance(v, int))
    dry_run = apply_setting != "true"
    record_job(
        "data_cleanup", ok=True,
        summary={"dryRun": dry_run, "removed": total},
        log_entry=True,
        message=("Data cleanup check (dry run): nothing deleted" if dry_run
                 else f"Data cleanup removed {total} old record(s)"),
    )

    response.headers["Cache-Control"] = "no-store"
    return report
