"""WellScreen server-owned security alerts.

Runs in FastAPI backend using Firebase Admin SDK. The /internal sweep must be
scheduled OUTSIDE the child app (e.g. Cloudflare Cron Trigger).
"""
from __future__ import annotations

import base64
import json
import logging
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any

from google.api_core.exceptions import AlreadyExists, Conflict

from .firebase_service import get_firestore_client
from .notification_service import send_alert_notification

log = logging.getLogger(__name__)
EVENT_TYPES = frozenset({
    "screen_time_limit_exceeded", "late_night_usage",
    "repeated_restricted_app_access", "restricted_content_attempt",
    "monitoring_permission_disabled",
    "usage_warning_threshold", "usage_high_threshold", "unhealthy_usage_pattern",
    "app_usage_warning_threshold", "app_usage_high_threshold",
})
EVENT_ID_PATTERN = re.compile(r"^[a-zA-Z0-9_-]{8,96}$")
E164_PATTERN = re.compile(r"^\+[1-9]\d{7,14}$")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _utc_datetime(value: Any) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def should_report_missing(last_seen: datetime | None, now: datetime, timeout_minutes: int) -> bool:
    """Never classify a child as missing before an actual server check-in."""
    if last_seen is None:
        return False
    return now - last_seen >= timedelta(minutes=timeout_minutes)


def incident_id(last_seen: datetime) -> str:
    # Stable across repeated sweeps, new after a genuinely new check-in.
    return "missing_" + str(int(last_seen.timestamp() * 1_000_000))


def _send_sms(*, parent_uid: str, message: str) -> dict[str, str]:
    """Explicit opt-in + verified number + provider config; never direct Android SMS."""
    if os.getenv("SMS_BACKUP_ENABLED", "false").lower() != "true":
        return {"status": "not_enabled"}
    db = get_firestore_client()
    user = db.collection("users").document(parent_uid).get().to_dict() or {}
    phone = (user.get("phoneNumber") or "").strip()
    # An app-generated toggle alone does not constitute consent/verification.
    if (not user.get("smsCriticalAlertsEnabled") or not user.get("smsConsentAt")
            or not user.get("phoneNumberVerified")
            or user.get("smsVerifiedPhoneNumber") != phone
            or not E164_PATTERN.fullmatch(phone)):
        return {"status": "missing_verified_consent_or_phone"}

    sid = os.getenv("TWILIO_ACCOUNT_SID", "")
    token = os.getenv("TWILIO_AUTH_TOKEN", "")
    origin = os.getenv("TWILIO_FROM_NUMBER", "")
    if not sid or not token or not E164_PATTERN.fullmatch(origin):
        return {"status": "provider_not_configured"}

    endpoint = f"https://api.twilio.com/2010-04-01/Accounts/{urllib.parse.quote(sid, safe='')}/Messages.json"
    payload = urllib.parse.urlencode({"From": origin, "To": phone, "Body": message[:1500]}).encode()
    req = urllib.request.Request(endpoint, data=payload, method="POST")
    basic = base64.b64encode(f"{sid}:{token}".encode()).decode()
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=15) as reply:
            data = json.loads(reply.read(4096).decode())
        # Accepted by provider is NOT proof it arrived on the parent's phone.
        return {"status": "accepted", "providerId": str(data.get("sid", ""))}
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        log.warning("SMS provider request failed: %s", type(exc).__name__)
        return {"status": "failed"}


def _push(*, parent_uid: str, title: str, message: str,
          alert_type: str, profile_id: str, event_id: str) -> dict[str, str]:
    try:
        result = send_alert_notification(
            caller_uid=parent_uid,  # Trusted server action; parent is recipient.
            parent_uid=parent_uid, title=title, body=message,
            data={"alertType": alert_type, "childProfileId": profile_id, "eventId": event_id},
        )
        return {"status": result.get("status", "failed"),
                "messageId": str(result.get("message_id") or "")}
    except Exception as exc:
        log.warning("Monitoring FCM failed for %s: %s", profile_id, type(exc).__name__)
        return {"status": "failed"}


def _create_and_dispatch(*, profile_id: str, parent_uid: str, alert_id: str,
                         kind: str, title: str, body: str, occurred_at: datetime,
                         details: dict[str, Any], force_sms: bool = False) -> bool:
    """Create-only alert claim prevents duplicate sends on repeat requests.

    Delivery is best effort: a worker crash between claiming and sending can
    leave the event recorded but unsent. Alert record captures the outcome.
    """
    db = get_firestore_client()
    alert_ref = (db.collection("child_profiles").document(profile_id)
                 .collection("monitoring_alerts").document(alert_id))
    try:
        alert_ref.create({
            "kind": kind, "parentId": parent_uid, "title": title, "body": body,
            "details": details, "occurredAt": occurred_at,
            "createdAt": _utcnow(), "pushStatus": "pending", "smsStatus": "pending",
        })
    except (AlreadyExists, Conflict):
        return False

    push = _push(parent_uid=parent_uid, title=title, message=body,
                 alert_type=kind, profile_id=profile_id, event_id=alert_id)
    sms = (_send_sms(parent_uid=parent_uid, message=f"{title}\n{body}")
           if force_sms or push["status"] != "sent" else {"status": "backup_not_needed"})
    alert_ref.update({"pushStatus": push["status"], "pushMessageId": push.get("messageId", ""),
                      "smsStatus": sms["status"], "smsProviderId": sms.get("providerId", ""),
                      "dispatchedAt": _utcnow()})
    return True


def _timeout_minutes() -> int:
    try:
        value = int(os.getenv("MONITORING_MISSING_TIMEOUT_MINUTES", "90"))
    except ValueError:
        value = 90
    return max(60, min(1440, value))


def sweep_missing_heartbeats() -> dict[str, int]:
    """Invoked by authenticated scheduler. Does not run in phone process."""
    db = get_firestore_client()
    now = _utcnow()
    timeout = _timeout_minutes()
    scanned = 0
    alerted = 0
    # For a small deployment; for scale add indexed pagination and filtering.
    for snapshot in db.collection("child_profiles").where(
        "pairingStatus", "==", "connected"
    ).stream():
        scanned += 1
        child = snapshot.to_dict() or {}
        parent_uid = child.get("parentId")
        if not isinstance(parent_uid, str) or not parent_uid:
            continue
        last_seen = _utc_datetime(child.get("lastSeenAt"))
        if not should_report_missing(last_seen, now, timeout):
            continue
        assert last_seen is not None
        name = str(child.get("deviceName") or child.get("name") or "Child's Device")[:100]
        last_label = last_seen.strftime("%Y-%m-%d %H:%M UTC")
        title = "WellScreen Security Alert"
        body = (f"{name} has not reported recently. Last seen: {last_label}. "
                "The device may be offline, powered off, or monitoring may be disabled/removed.")
        alert_id = incident_id(last_seen)
        if _create_and_dispatch(
            profile_id=snapshot.id, parent_uid=parent_uid, alert_id=alert_id,
            kind="no_recent_connection", title=title, body=body,
            occurred_at=last_seen, details={"lastSeenAt": last_label, "deviceName": name,
                                           "status": "no_recent_connection"},
            force_sms=True,
        ):
            # Shown on the existing parent child_profiles snapshot, so no new
            # Firestore subcollection read rule is needed to display the banner.
            snapshot.reference.update({"monitoringSecurityAlert": {
                "eventId": alert_id, "type": "no_recent_connection",
                "deviceName": name, "lastSeenAt": last_seen,
                "createdAt": now,
            }})
            alerted += 1
    return {"scanned": scanned, "newAlerts": alerted, "timeoutMinutes": timeout}


def accept_child_events(*, child_uid: str, profile_id: str,
                        events: list[dict[str, Any]]) -> dict[str, Any]:
    """Validate pairing and acknowledge each event ID after persistent creation."""
    db = get_firestore_client()
    profile = db.collection("child_profiles").document(profile_id).get()
    child = profile.to_dict() or {}
    if child.get("pairingStatus") != "connected" or child.get("childAccountId") != child_uid:
        raise PermissionError("Not a paired child account")
    parent_uid = child.get("parentId")
    if not isinstance(parent_uid, str) or not parent_uid:
        raise PermissionError("Missing paired parent")

    recognized: list[str] = []
    for event in events[:50]:
        kind = event.get("type")
        event_id = event.get("eventId")
        if kind not in EVENT_TYPES or not isinstance(event_id, str) or not EVENT_ID_PATTERN.fullmatch(event_id):
            continue
        when_ms = event.get("timestampMs")
        if type(when_ms) is not int or not (0 < when_ms <= int(_utcnow().timestamp() * 1000) + 300_000):
            continue
        when = datetime.fromtimestamp(when_ms / 1000, tz=timezone.utc)
        if when < _utcnow() - timedelta(days=30):
            continue
        subject = str(event.get("subject") or "")[:150]
        label = str(event.get("label") or subject or "an application")[:150]
        descriptions = {
            "screen_time_limit_exceeded": ("Screen-time limit reached", f"A time limit was reached for {label}."),
            "late_night_usage": ("Late-night device usage", f"Device use was detected during configured restricted hours ({label})."),
            "repeated_restricted_app_access": ("Repeated restricted app attempts", f"Repeated access attempts were detected for {label}."),
            "restricted_content_attempt": ("Restricted content access attempted", f"An attempt was made to access restricted content: {label}."),
            "monitoring_permission_disabled": ("Monitoring permission disabled", f"A required WellScreen monitoring permission is unavailable: {label}."),
            "usage_warning_threshold": ("Screen-time warning", f"Your child's device reached {label} of use."),
            "usage_high_threshold": ("High screen-time usage", f"Your child's device reached {label} of use."),
            "unhealthy_usage_pattern": ("Unhealthy usage pattern detected", f"Usage pattern flagged: {label}."),
            "app_usage_warning_threshold": ("App usage warning", f"Long use of one app today: {label}."),
            "app_usage_high_threshold": ("High single-app usage", f"Very long use of one app today: {label}."),
        }
        title, body = descriptions[kind]
        # Stable client IDs are deduplicated by Firestore document creation.
        # Acknowledging a duplicate means the child can drop its local copy.
        _create_and_dispatch(profile_id=profile_id, parent_uid=parent_uid,
                             alert_id="child_" + event_id, kind=kind,
                             title=title, body=body, occurred_at=when,
                             details={"subject": subject, "label": label})
        recognized.append(event_id)
    return {"acceptedEventIds": recognized}


def _twilio_verify_request(endpoint: str, fields: dict[str, str]) -> dict[str, Any]:
    """Twilio Verify API; use server credentials, never ship to Android."""
    sid, token = os.getenv("TWILIO_ACCOUNT_SID", ""), os.getenv("TWILIO_AUTH_TOKEN", "")
    service_sid = os.getenv("TWILIO_VERIFY_SERVICE_SID", "")
    if not sid or not token or not service_sid:
        raise RuntimeError("Twilio Verify is not configured")
    url = ("https://verify.twilio.com/v2/Services/" +
           urllib.parse.quote(service_sid, safe="") + "/" + endpoint)
    request = urllib.request.Request(
        url, data=urllib.parse.urlencode(fields).encode(), method="POST",
    )
    request.add_header("Authorization", "Basic " +
                       base64.b64encode(f"{sid}:{token}".encode()).decode())
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read(8192).decode())


def _verified_parent_doc(uid: str):
    """Only the signed-in parent may opt their own number into SMS."""
    doc = get_firestore_client().collection("users").document(uid)
    raw = doc.get().to_dict() or {}
    if raw.get("role") != "parent":
        raise PermissionError("Parent account required")
    return doc, raw


def begin_parent_sms_opt_in(*, uid: str, phone: str, consent: bool) -> dict[str, str]:
    if not consent or not E164_PATTERN.fullmatch(phone):
        raise ValueError("Explicit consent and an E.164 number are required")
    doc, old = _verified_parent_doc(uid)
    if _utcnow() - (_utc_datetime(old.get("smsVerificationStartedAt")) or datetime(1970, 1, 1, tzinfo=timezone.utc)) < timedelta(seconds=60):
        raise ValueError("Wait before requesting another verification code")
    data = _twilio_verify_request("Verifications", {"To": phone, "Channel": "sms"})
    if data.get("status") not in ("pending", "approved"):
        raise RuntimeError("Verification request was not accepted")
    # Verification pending; do NOT enable SMS until code is confirmed.
    doc.update({"smsVerificationPhone": phone, "smsVerificationStartedAt": _utcnow()})
    return {"status": "verification_sent"}


def confirm_parent_sms_opt_in(*, uid: str, code: str) -> dict[str, str]:
    if not re.fullmatch(r"[0-9]{4,10}", code):
        raise ValueError("Invalid verification code")
    doc, old = _verified_parent_doc(uid)
    phone = old.get("smsVerificationPhone")
    started = _utc_datetime(old.get("smsVerificationStartedAt"))
    if not isinstance(phone, str) or not E164_PATTERN.fullmatch(phone) or not started:
        raise ValueError("No pending number verification")
    if _utcnow() - started > timedelta(minutes=15):
        raise ValueError("Verification expired")
    data = _twilio_verify_request("VerificationCheck", {"To": phone, "Code": code})
    if data.get("status") != "approved":
        raise ValueError("Verification was not approved")
    # Use server-side verification. Stores consent timestamp and binds it to
    # the exact number; changing a profile number won't silently authorize it.
    doc.update({"phoneNumber": phone, "smsVerifiedPhoneNumber": phone,
                "phoneNumberVerified": True,
                "smsCriticalAlertsEnabled": True,
                "smsConsentAt": _utcnow(),
                "smsVerificationPhone": None,
                "smsVerificationStartedAt": None})
    return {"status": "enabled"}


def disable_parent_sms_opt_in(*, uid: str) -> dict[str, str]:
    doc, _ = _verified_parent_doc(uid)
    doc.update({"smsCriticalAlertsEnabled": False,
                "smsAlertsDisabledAt": _utcnow()})
    return {"status": "disabled"}
