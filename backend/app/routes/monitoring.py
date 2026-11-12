"""Add router to backend/app/main.py: app.include_router(monitoring.router)."""
from __future__ import annotations

import hmac
import os
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.services.monitoring_alerts_service import (
    accept_child_events, sweep_missing_heartbeats,
    begin_parent_sms_opt_in, confirm_parent_sms_opt_in, disable_parent_sms_opt_in,
)
from app.services.user_auth_service import require_user

router = APIRouter(tags=["Monitoring"])


class ChildEventsRequest(BaseModel):
    childProfileId: str = Field(min_length=1, max_length=128)
    events: list[dict[str, Any]] = Field(min_length=1, max_length=50)


@router.post("/monitoring/events")
def receive_child_events(payload: ChildEventsRequest,
                         current_user: dict = Depends(require_user)):
    uid = current_user.get("uid")
    if not isinstance(uid, str) or not uid:
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        return accept_child_events(child_uid=uid, profile_id=payload.childProfileId,
                                   events=payload.events)
    except PermissionError:
        raise HTTPException(status_code=403, detail="Child pairing not authorized") from None


class SmsOptInStart(BaseModel):
    phone: str = Field(min_length=8, max_length=16)
    consent: bool


class SmsOptInConfirm(BaseModel):
    code: str = Field(min_length=4, max_length=10)


def _uid_or_401(current_user: dict) -> str:
    uid = current_user.get("uid")
    if not isinstance(uid, str) or not uid:
        raise HTTPException(status_code=401, detail="Authentication required")
    return uid


@router.post("/monitoring/sms/opt-in/start")
def sms_opt_in_start(payload: SmsOptInStart, current_user: dict = Depends(require_user)):
    try:
        return begin_parent_sms_opt_in(
            uid=_uid_or_401(current_user), phone=payload.phone, consent=payload.consent,
        )
    except PermissionError:
        raise HTTPException(status_code=403, detail="Parent account required") from None
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/monitoring/sms/opt-in/confirm")
def sms_opt_in_confirm(payload: SmsOptInConfirm, current_user: dict = Depends(require_user)):
    try:
        return confirm_parent_sms_opt_in(uid=_uid_or_401(current_user), code=payload.code)
    except PermissionError:
        raise HTTPException(status_code=403, detail="Parent account required") from None
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/monitoring/sms/opt-out")
def sms_opt_out(current_user: dict = Depends(require_user)):
    try:
        return disable_parent_sms_opt_in(uid=_uid_or_401(current_user))
    except PermissionError:
        raise HTTPException(status_code=403, detail="Parent account required") from None


@router.post("/internal/monitoring/sweep")
def sweep(x_monitoring_secret: str | None = Header(default=None)):
    secret = os.getenv("MONITORING_CRON_SECRET", "")
    if not secret or not x_monitoring_secret or not hmac.compare_digest(secret, x_monitoring_secret):
        raise HTTPException(status_code=403, detail="Forbidden")
    return sweep_missing_heartbeats()
