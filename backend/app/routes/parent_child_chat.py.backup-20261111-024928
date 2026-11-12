"""Register via app.include_router(parent_child_chat.router)."""
from __future__ import annotations

import os
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ..services.chat_access_service import (
    ChatAccessError, activate_grant, authenticated_uid,
    respond_to_request, sweep_chat_notifications,
)

router = APIRouter(tags=["Parent-child chat"])


class DecisionBody(BaseModel):
    approve: bool
    approvedMinutes: int | None = Field(default=None, ge=1, le=180)


@router.post("/chat/requests/{profile_id}/{request_id}/decision")
def decide(profile_id: str, request_id: str, body: DecisionBody,
           authorization: str | None = Header(default=None)):
    try:
        uid = authenticated_uid(authorization)
        return respond_to_request(parent_uid=uid, profile_id=profile_id,
                                  request_id=request_id, approve=body.approve,
                                  approved_minutes=body.approvedMinutes)
    except ChatAccessError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/chat/grants/{profile_id}/{package_name}/activate")
def activate(profile_id: str, package_name: str,
             authorization: str | None = Header(default=None)):
    try:
        uid = authenticated_uid(authorization)
        return activate_grant(child_uid=uid, profile_id=profile_id,
                              package_name=package_name)
    except ChatAccessError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/internal/chat/notifications/sweep")
def sweep(x_chat_cron_secret: str | None = Header(default=None)):
    expected = os.environ.get("CHAT_CRON_SECRET")
    if not expected or not x_chat_cron_secret or x_chat_cron_secret != expected:
        raise HTTPException(status_code=403, detail="Unauthorized")
    return sweep_chat_notifications()
