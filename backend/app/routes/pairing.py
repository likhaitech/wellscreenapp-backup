"""Parent-child device pairing API routes."""
from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ..services.chat_access_service import (
    ChatAccessError,
    authenticated_uid,
)
from ..services.pairing_service import (
    PairingConflictError,
    PairingError,
    PairingForbiddenError,
    PairingRateLimitError,
    generate_pairing_code,
    redeem_pairing_code,
)


router = APIRouter(tags=["Device pairing"])


class GeneratePairingCodeBody(BaseModel):
    childName: str = Field(min_length=1, max_length=100)


class RedeemPairingCodeBody(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


def _get_authenticated_uid(authorization: str | None) -> str:
    try:
        return authenticated_uid(authorization)
    except ChatAccessError as error:
        raise HTTPException(
            status_code=401,
            detail=str(error),
        ) from error


@router.post("/pairing/code")
def create_code(
    body: GeneratePairingCodeBody,
    authorization: str | None = Header(default=None),
):
    """Generate a pairing code for an authenticated parent."""

    uid = _get_authenticated_uid(authorization)

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
