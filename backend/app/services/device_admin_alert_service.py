"""In-app record for Device Admin (uninstall protection) alerts.

The child's phone sends these through POST /alerts/notify. A push alone can
be missed or swiped away, so the backend also saves one document in
child_profiles/{profileId}/monitoring_alerts - the collection the guardian's
Notifications screen already reads. Written with the Admin SDK, so
firestore.rules does not change. Saved even when the push fails.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from google.api_core.exceptions import AlreadyExists, Conflict

from .firebase_service import get_firestore_client

DEVICE_ADMIN_ALERTS: dict[str, dict[str, str]] = {
    "device_admin_disable_attempt": {
        "severity": "warning",
        "title": "Uninstall protection: turn-off attempt",
        "body": "Your child tried to turn off uninstall protection.",
    },
    "device_admin_disabled": {
        "severity": "danger",
        "title": "Uninstall protection turned off",
        "body": "Uninstall protection was turned off - WellScreen can now "
                "be uninstalled.",
    },
}

# Child phones send milliseconds since epoch; reject anything outside
# 2020-01-01 .. 2100-01-01 so a bad value cannot become a weird document ID.
_MIN_MS = 1_577_836_800_000
_MAX_MS = 4_102_444_800_000


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def record_device_admin_alert(
    *,
    caller_uid: str,
    parent_uid: str,
    alert_type: str,
    data: dict[str, Any] | None,
    push_status: str,
) -> str:
    """Save the in-app record. Returns "saved", "duplicate" or "skipped".

    Only the child account paired to that profile, sending to its own
    guardian, can create a record.
    """
    spec = DEVICE_ADMIN_ALERTS.get(alert_type)
    if spec is None:
        return "skipped"

    data = data or {}
    profile_id = data.get("childProfileId")
    if not isinstance(profile_id, str) or not profile_id or "/" in profile_id:
        return "skipped"

    db = get_firestore_client()
    profile_ref = db.collection("child_profiles").document(profile_id)
    profile = profile_ref.get().to_dict() or {}
    if profile.get("childAccountId") != caller_uid:
        return "skipped"
    if profile.get("parentId") != parent_uid:
        return "skipped"

    timestamp_ms = data.get("timestampMs")
    if type(timestamp_ms) is not int or not (_MIN_MS <= timestamp_ms <= _MAX_MS):
        timestamp_ms = int(_utcnow().timestamp() * 1000)
    occurred_at = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)

    # One record per event: the phone retries the same timestamp after
    # being offline, and that must not create a second entry.
    alert_id = f"{alert_type}_{timestamp_ms}"
    try:
        profile_ref.collection("monitoring_alerts").document(alert_id).create({
            "kind": alert_type,
            "parentId": parent_uid,
            "title": spec["title"],
            "body": spec["body"],
            "severity": spec["severity"],
            "details": {"timestampMs": timestamp_ms},
            "occurredAt": occurred_at,
            "createdAt": _utcnow(),
            "pushStatus": push_status,
            "smsStatus": "not_requested",
        })
    except (AlreadyExists, Conflict):
        return "duplicate"
    return "saved"
