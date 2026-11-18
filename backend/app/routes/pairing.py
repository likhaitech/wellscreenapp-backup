"""Parent-child device pairing API routes."""
from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ..services.chat_access_service import (
    ChatAccessError,
    authenticated_uid,
)
from ..services.email_verification_service import (
    EmailNotVerifiedError,
    ensure_email_verified,
)
from ..services.pairing_service import (
    PairingConflictError,
    PairingError,
    PairingForbiddenError,
    PairingRateLimitError,
    generate_pairing_code,
    redeem_pairing_code,
    unpair_child_device,
)


router = APIRouter(tags=["Device pairing"])


class GeneratePairingCodeBody(BaseModel):
    childName: str = Field(min_length=1, max_length=100)


class RedeemPairingCodeBody(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")

class UnpairChildDeviceBody(BaseModel):
    childProfileId: str = Field(
        min_length=1,
        max_length=128,
        pattern=r"^[A-Za-z0-9_-]+$",
    )

def _get_authenticated_uid(authorization: str | None) -> str:
    try:
        return authenticated_uid(authorization)
    except ChatAccessError as error:
        raise HTTPException(
            status_code=401,
            detail=str(error),
        ) from error


# The app looks for this header to show its "Verify your email" dialog.
EMAIL_NOT_VERIFIED_HEADER = {"X-WellScreen-Error": "email_not_verified"}


def _require_verified_email(uid: str) -> None:
    try:
        ensure_email_verified(uid)
    except EmailNotVerifiedError as error:
        raise HTTPException(
            status_code=403,
            detail=str(error),
            headers=EMAIL_NOT_VERIFIED_HEADER,
        ) from error
    except Exception as error:
        # Fail closed: never pair when the account could not be checked.
        raise HTTPException(
            status_code=503,
            detail="Could not check your account right now. Please try again.",
        ) from error


@router.post("/pairing/code")
def create_code(
    body: GeneratePairingCodeBody,
    authorization: str | None = Header(default=None),
):
    """Generate a pairing code for an authenticated parent."""

    uid = _get_authenticated_uid(authorization)
    _require_verified_email(uid)

    try:
        return generate_pairing_code(
            parent_uid=uid,
            child_name=body.childName,
        )

    except PairingForbiddenError as error:
        raise HTTPException(
            status_code=403,
            detail=str(error),
        ) from error

    except PairingError as error:
        raise HTTPException(
            status_code=400,
            detail=str(error),
        ) from error


@router.post("/pairing/redeem")
def redeem_code(
    body: RedeemPairingCodeBody,
    authorization: str | None = Header(default=None),
):
    """Redeem a pairing code for an authenticated child."""

    # No email check here: a child may have no email of their own, and can
    # only link with a code created by a guardian whose email is verified.
    uid = _get_authenticated_uid(authorization)

    try:
        return redeem_pairing_code(
            child_uid=uid,
            code=body.code,
        )

    except PairingRateLimitError as error:
        raise HTTPException(
            status_code=429,
            detail=str(error),
        ) from error

    except PairingConflictError as error:
        raise HTTPException(
            status_code=409,
            detail=str(error),
        ) from error

    except PairingForbiddenError as error:
        raise HTTPException(
            status_code=403,
            detail=str(error),
        ) from error

    except PairingError as error:
        raise HTTPException(
            status_code=400,
            detail=str(error),
        ) from error



@router.post("/pairing/unpair")
def unpair_device(
    body: UnpairChildDeviceBody,
    authorization: str | None = Header(default=None),
):
    """Remove a child device from its owning parent."""

    uid = _get_authenticated_uid(authorization)

    try:
        return unpair_child_device(
            parent_uid=uid,
            child_profile_id=body.childProfileId,
        )

    except PairingConflictError as error:
        raise HTTPException(
            status_code=409,
            detail=str(error),
        ) from error

    except PairingForbiddenError as error:
        raise HTTPException(
            status_code=403,
            detail=str(error),
        ) from error

    except PairingError as error:
        raise HTTPException(
            status_code=400,
            detail=str(error),
        ) from error