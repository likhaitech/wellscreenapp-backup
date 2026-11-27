"""Admin dashboard data: daily active totals and background job status.

Counts only - no family's activity is returned.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.services.admin_auth_service import require_admin
from app.services.server_info import server_info
from app.services.system_activity_service import admin_overview, refresh_daily_activity

router = APIRouter(prefix="/admin/overview", tags=["Admin Overview"])


@router.get("/")
def read_overview(
    days: int = Query(default=7, ge=1, le=30),
    current_admin: dict = Depends(require_admin),
):
    # Recount today first, so the admin sees who is active right now
    # instead of waiting for the next 5-minute monitoring check.
    refresh_daily_activity()
    try:
        return {**admin_overview(days=days), "server": server_info()}
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=type(exc).__name__,
        ) from None
