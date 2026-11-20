"""Which server version (patch) is running, and a record of each new one.

A WellScreen system patch is a code change: it is pushed to GitHub and
Render redeploys the backend. Render sets RENDER_GIT_COMMIT for the running
build; when a build that hasn't been seen before starts, it is recorded as
"server_patch_deployed" in System logs so the admin can see the patch
landed (Render's free tier restarts the same build often - those are not
recorded again).
"""
from __future__ import annotations

import datetime as dt
import logging
import os
from typing import Any, Callable

from firebase_admin import firestore

from .firebase_service import get_firestore_client
from .system_log_service import create_system_log

logger = logging.getLogger(__name__)

SERVER_VERSION = (os.getenv("RENDER_GIT_COMMIT") or "").strip()[:7] or "local"
STARTED_AT = dt.datetime.now(dt.timezone.utc)


def server_info() -> dict[str, str]:
    return {
        "version": SERVER_VERSION,
        "running_since": STARTED_AT.isoformat(),
    }


def record_deploy(
    *,
    version: str = SERVER_VERSION,
    get_db: Callable[[], Any] = get_firestore_client,
    log: Callable[..., None] = create_system_log,
) -> bool:
    """Logs this server version once. True when it was new."""
    if version == "local":
        return False
    ref = get_db().collection("system_settings").document("global")
    snapshot = ref.get()
    previous = (snapshot.to_dict() or {}).get("server_version") if snapshot.exists else None
    if previous == version:
        return False
    ref.set(
        {
            "server_version": version,
            "server_deployed_at": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )
    log(
        level="info",
        action="server_patch_deployed",
        message=f"Server patch {version} deployed",
        details={"version": version, "previous": previous},
    )
    return True


def record_deploy_safely() -> None:
    try:
        record_deploy()
    except Exception:  # never stop the server from starting
        logger.exception("Could not record the server deploy")
