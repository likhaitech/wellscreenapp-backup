"""Register via app.include_router(parent_child_chat.router)."""
from __future__ import annotations
import hmac
import logging

import os
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ..services.chat_access_service import (
    AppRequestLimitError, ChatAccessError, activate_grant, authenticated_uid,
    dispatch_event, respond_to_request, submit_access_request,
    sweep_chat_notifications,
)

router = APIRouter(tags=["Parent-child chat"])


class DecisionBody(BaseModel):
    approve: bool
    approvedMinutes: int | None = Field(default=None, ge=1, le=180)


class AccessRequestBody(BaseModel):
    packageName: str = Field(min_length=3, max_length=200)
    requestedMinutes: int = Field(strict=True, ge=5, le=120)


@router.post("/chat/requests/{profile_id}/{request_id}")
def submit_request(
    profile_id: str, request_id: str, body: AccessRequestBody,
    authorization: str | None = Header(default=None),
):
    try:
        uid = authenticated_uid(authorization)
        return submit_access_request(
            child_uid=uid, profile_id=profile_id, request_id=request_id,
            package_name=body.packageName,
            requested_minutes=body.requestedMinutes,
        )
    except AppRequestLimitError as error:
        raise HTTPException(status_code=429, detail=str(error)) from error
    except ChatAccessError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/chat/requests/{profile_id}/{request_id}/decision")
def decide(profile_id: str, request_id: str, body: DecisionBody,
           authorization: str | None = Header(default=None)):
    try:
        uid = authenticated_uid(authorization)
        return respond_to_request(parent_uid=uid, profile_id=profile_id,
                                  request_id=request_id, approve=body.approve,
                                  approved_minutes=body.approvedMinutes)
    except ChatAccessError as error:
        logging.getLogger(__name__).warning(
            "WellScreen approval rejected: reason=%s",
            str(error),
        )
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/chat/events/{profile_id}/{kind}/{event_id}/dispatch")
def dispatch(profile_id: str, kind: str, event_id: str,
             authorization: str | None = Header(default=None)):
    try:
        uid = authenticated_uid(authorization)
        return dispatch_event(caller_uid=uid, profile_id=profile_id,
                              kind=kind, event_id=event_id)
    except ChatAccessError as error:
        logging.getLogger(__name__).warning(
            "WellScreen chat dispatch rejected: reason=%s", str(error))
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
    if (
        not expected
        or not x_chat_cron_secret
        or not hmac.compare_digest(x_chat_cron_secret, expected)
    ):
        raise HTTPException(status_code=403, detail="Unauthorized")
    return sweep_chat_notifications()
