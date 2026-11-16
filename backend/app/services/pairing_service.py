"""Secure parent-child device pairing operations.

Pairing codes are generated and redeemed exclusively by the trusted
FastAPI backend using Firebase Admin SDK.
"""
from __future__ import annotations

import datetime as dt
import re
import secrets
from typing import Any

from firebase_admin import firestore
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1 import transactional

from .firebase_service import get_firestore_client


UTC = dt.timezone.utc

PAIRING_CODE_TTL = dt.timedelta(minutes=15)
PAIRING_CODE_PATTERN = re.compile(r"^\d{6}$")

MAX_CODE_GENERATION_ATTEMPTS = 25
MAX_REDEMPTION_ATTEMPTS = 10
REDEMPTION_WINDOW = dt.timedelta(minutes=15)


class PairingError(ValueError):
    """Base error for pairing operations."""


class PairingForbiddenError(PairingError):
    """The authenticated account is not authorized to pair."""


class PairingConflictError(PairingError):
    """The account or pairing code is already connected."""


class PairingRateLimitError(PairingError):
    """Too many pairing-code redemption attempts."""


def _now() -> dt.datetime:
    return dt.datetime.now(UTC)


def _as_utc(value: dt.datetime) -> dt.datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _valid_uid(uid: str) -> bool:
    return (
        isinstance(uid, str)
        and bool(uid)
        and "/" not in uid
        and len(uid) <= 128
    )


def generate_pairing_code(
    *,
    parent_uid: str,
    child_name: str,
) -> dict[str, Any]:
    """Generate a unique six-digit code and waiting child profile."""

    if not _valid_uid(parent_uid):
        raise PairingForbiddenError("Invalid parent account.")

    child_name = child_name.strip() if isinstance(child_name, str) else ""

    if not child_name or len(child_name) > 100:
        raise PairingError("Child name must contain 1 to 100 characters.")

    db = get_firestore_client()

    parent_ref = db.collection("users").document(parent_uid)

    for _ in range(MAX_CODE_GENERATION_ATTEMPTS):
        code = str(secrets.randbelow(900000) + 100000)

        code_ref = db.collection("pairing_codes").document(code)
        profile_ref = db.collection("child_profiles").document()

        now = _now()
        expires_at = now + PAIRING_CODE_TTL

        @transactional
        def create_pairing(transaction: Any) -> None:
            parent_snapshot = parent_ref.get(transaction=transaction)

            if not parent_snapshot.exists:
                raise PairingForbiddenError("Parent account not found.")

            parent_data = parent_snapshot.to_dict() or {}

            if parent_data.get("role") != "parent":
                raise PairingForbiddenError(
                    "Only parent accounts can generate pairing codes."
                )

            parent_name = str(
                parent_data.get("fullName")
                or parent_data.get("displayName")
                or parent_data.get("name")
                or ""
            ).strip()

            parent_email = str(
                parent_data.get("email") or ""
            ).strip()

            profile_data = {
                "id": profile_ref.id,
                "parentId": parent_uid,
                "name": child_name,
                "pairingStatus": "waiting",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }

            if parent_name:
                profile_data["parentDisplayName"] = parent_name

            if parent_email:
                profile_data["parentEmail"] = parent_email

            code_data = {
                "code": code,
                "parentId": parent_uid,
                "childId": profile_ref.id,
                "childName": child_name,
                "status": "active",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "expiresAt": expires_at,
            }

            # Both documents are created atomically.
            # An existing code cannot be overwritten.
            transaction.create(profile_ref, profile_data)
            transaction.create(code_ref, code_data)

        try:
            create_pairing(db.transaction())

            return {
                "code": code,
                "childProfileId": profile_ref.id,
                "expiresAt": expires_at.isoformat(),
            }

        except AlreadyExists:
            # Generate another code if the six-digit ID is occupied.
            continue

    raise PairingError(
        "Unable to generate a unique pairing code. Please try again."
    )


def _consume_redemption_attempt(
    db: Any,
    child_uid: str,
) -> None:
    """Apply a per-account redemption limit.

    Maximum: 10 attempts per 15-minute window.
    Invalid codes also consume an attempt.
    """

    now = _now()

    limit_ref = (
        db.collection("pairing_attempt_limits")
        .document(child_uid)
    )

    @transactional
    def consume(transaction: Any) -> None:
        snapshot = limit_ref.get(transaction=transaction)
        data = snapshot.to_dict() or {}

        window_started = data.get("windowStartedAt")
        count = data.get("attemptCount", 0)

        if not isinstance(count, int) or isinstance(count, bool):
            count = 0

        if isinstance(window_started, dt.datetime):
            window_started = _as_utc(window_started)

            if now - window_started < REDEMPTION_WINDOW:
                if count >= MAX_REDEMPTION_ATTEMPTS:
                    raise PairingRateLimitError(
                        "Too many pairing attempts. Please try again later."
                    )
            else:
                window_started = now
                count = 0
        else:
            window_started = now
            count = 0

        transaction.set(
            limit_ref,
            {
                "windowStartedAt": window_started,
                "attemptCount": count + 1,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    consume(db.transaction())


def redeem_pairing_code(
    *,
    child_uid: str,
    code: str,
) -> dict[str, str]:
    """Redeem a pairing code and atomically connect the child account."""

    if not _valid_uid(child_uid):
        raise PairingForbiddenError("Invalid child account.")

    if not isinstance(code, str) or not PAIRING_CODE_PATTERN.fullmatch(code):
        raise PairingError("Please enter a valid 6-digit pairing code.")

    db = get_firestore_client()

    child_ref = db.collection("users").document(child_uid)

    # Check that the caller has a registered child account.
    child_snapshot = child_ref.get()

    if not child_snapshot.exists:
        raise PairingForbiddenError("Child account not found.")

    child_data = child_snapshot.to_dict() or {}

    if child_data.get("role") != "child":
        raise PairingForbiddenError(
            "Only child accounts can redeem pairing codes."
        )

    _consume_redemption_attempt(db, child_uid)

    code_ref = db.collection("pairing_codes").document(code)

    now = _now()

    @transactional
    def redeem(transaction: Any) -> dict[str, str]:
        code_snapshot = code_ref.get(transaction=transaction)

        if not code_snapshot.exists:
            raise PairingError("Pairing code not found.")

        code_data = code_snapshot.to_dict() or {}

        parent_uid = str(code_data.get("parentId") or "")
        profile_id = str(code_data.get("childId") or "")

        if (
            not _valid_uid(parent_uid)
            or not profile_id
            or "/" in profile_id
        ):
            raise PairingError("Invalid pairing code data.")

        profile_ref = (
            db.collection("child_profiles").document(profile_id)
        )
        parent_ref = db.collection("users").document(parent_uid)

        # Read all documents before performing any transaction writes.
        profile_snapshot = profile_ref.get(transaction=transaction)
        parent_snapshot = parent_ref.get(transaction=transaction)
        current_child_snapshot = child_ref.get(transaction=transaction)

        if not profile_snapshot.exists or not parent_snapshot.exists:
            raise PairingError("Pairing profile is no longer available.")

        profile_data = profile_snapshot.to_dict() or {}
        parent_data = parent_snapshot.to_dict() or {}
        current_child_data = current_child_snapshot.to_dict() or {}

        if parent_data.get("role") != "parent":
            raise PairingError("Invalid parent account.")

        if current_child_data.get("role") != "child":
            raise PairingForbiddenError("Invalid child account.")

        if profile_data.get("parentId") != parent_uid:
            raise PairingError("Pairing profile ownership mismatch.")

        status = code_data.get("status")

        # Make a repeated request safe if the previous response was lost.
        if status == "connected":
            if (
                code_data.get("childAccountId") == child_uid
                and profile_data.get("childAccountId") == child_uid
                and current_child_data.get("pairedChildProfileId")
                == profile_id
            ):
                return {
                    "parentId": parent_uid,
                    "childProfileId": profile_id,
                    "status": "connected",
                }

            raise PairingConflictError(
                "This pairing code has already been used."
            )

        if status != "active":
            raise PairingError(
                "This pairing code is no longer active."
            )

        expires_at = code_data.get("expiresAt")

        if not isinstance(expires_at, dt.datetime):
            raise PairingError("Pairing code has an invalid expiration.")

        if now >= _as_utc(expires_at):
            raise PairingError("This pairing code has expired.")

        if profile_data.get("pairingStatus") != "waiting":
            raise PairingConflictError(
                "This child profile is no longer available."
            )

        if profile_data.get("childAccountId"):
            raise PairingConflictError(
                "This child profile is already connected."
            )

        if (
            current_child_data.get("pairedChildProfileId")
            or current_child_data.get("pairedParentId")
            or current_child_data.get("pairingStatus") == "connected"
        ):
            raise PairingConflictError(
                "This child account is already paired."
            )

        child_email = current_child_data.get("email")

        # All authorization checks have passed. Commit the three
        # related document updates atomically.
        transaction.update(
            code_ref,
            {
                "status": "connected",
                "childAccountId": child_uid,
                "childEmail": child_email,
                "connectedAt": firestore.SERVER_TIMESTAMP,
            },
        )

        transaction.update(
            profile_ref,
            {
                "childAccountId": child_uid,
                "childEmail": child_email,
                "pairingStatus": "connected",
                "connectedAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
        )

        transaction.set(
            child_ref,
            {
                "uid": child_uid,
                "email": child_email,
                "fullName": (
                    current_child_data.get("fullName")
                    or "Student User"
                ),
                "role": "child",
                "pairingStatus": "connected",
                "pairedParentId": parent_uid,
                "pairedChildProfileId": profile_id,
                "pairingCode": code,
                "pairedAt": firestore.SERVER_TIMESTAMP,
                "lastLoginAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

        return {
            "parentId": parent_uid,
            "childProfileId": profile_id,
            "status": "connected",
        }

    return redeem(db.transaction())
