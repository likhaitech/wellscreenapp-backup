"""WellScreen chat request decisions and temporary access grants.

Backend-authored approvals only. Existing emergencyAccess and app_rules stay untouched.
Requires existing firebase_service.get_firestore_client().
"""
from __future__ import annotations

import datetime as dt
from typing import Any

from firebase_admin import auth, firestore, messaging
from google.cloud.firestore_v1 import transactional

from .firebase_service import get_firestore_client

UTC = dt.timezone.utc
MAX_APPROVED_MINUTES = 180


class ChatAccessError(ValueError):
    pass


def authenticated_uid(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise ChatAccessError("Firebase authentication required")
    try:
        claims = auth.verify_id_token(authorization[7:].strip(), check_revoked=True)
        return str(claims["uid"])
    except Exception as exc:
        raise ChatAccessError("Invalid or expired Firebase session") from exc


def _paired_profile(db: Any, profile_id: str) -> dict[str, Any]:
    if not profile_id or "/" in profile_id:
        raise ChatAccessError("Invalid child profile")
    snap = db.collection("child_profiles").document(profile_id).get()
    if not snap.exists:
        raise ChatAccessError("Child profile not found")
    data = snap.to_dict() or {}
    if not data.get("parentId") or not data.get("childAccountId"):
        raise ChatAccessError("Profile is not paired")
    return data


def _restricted_rule(db: Any, parent_uid: str, package: str) -> dict[str, Any] | None:
    snap = db.collection("app_rules").document(parent_uid).get()
    rules = (snap.to_dict() or {}).get("rules", [])
    for rule in rules:
        if (isinstance(rule, dict) and rule.get("packageName") == package and
                rule.get("restrictEnabled") is True):
            return rule
    return None


def respond_to_request(*, parent_uid: str, profile_id: str, request_id: str,
                       approve: bool, approved_minutes: int | None) -> dict[str, Any]:
    db = get_firestore_client()
    profile = _paired_profile(db, profile_id)
    if profile["parentId"] != parent_uid:
        raise ChatAccessError("Only the paired parent can decide")
    if approve and (not isinstance(approved_minutes, int) or
                    isinstance(approved_minutes, bool) or
                    not 1 <= approved_minutes <= MAX_APPROVED_MINUTES):
        raise ChatAccessError("Approved time must be 1–180 minutes")
    req_ref = db.collection("child_profiles").document(profile_id).collection(
        "access_requests").document(request_id)
    now = dt.datetime.now(UTC)

    @transactional
    def decide(tx: Any) -> dict[str, Any]:
        snap = req_ref.get(transaction=tx)
        if not snap.exists:
            raise ChatAccessError("Request does not exist")
        data = snap.to_dict() or {}
        if data.get("childUid") != profile["childAccountId"]:
            raise ChatAccessError("Request does not belong to this child")
        if data.get("status") != "pending":
            raise ChatAccessError("This request was already decided")
        pkg = data.get("packageName", "")
        if not isinstance(pkg, str) or not pkg or "/" in pkg:
            raise ChatAccessError("Invalid application package")
        grant_ref = db.collection("child_profiles").document(profile_id).collection(
            "temporary_access_grants").document(pkg)
        prior = grant_ref.get(transaction=tx) if approve else None
        if approve and prior is not None and prior.exists:
            earlier = prior.to_dict() or {}
            previous_expiry = earlier.get("expiresAt")
            if earlier.get("state") == "pending_activation" or (
                earlier.get("state") == "active" and previous_expiry and previous_expiry > now
            ):
                raise ChatAccessError("Another grant is already active or awaiting activation")
        authoritative_rule = _restricted_rule(db, parent_uid, pkg) if approve else None
        if approve and authoritative_rule is None:
            raise ChatAccessError("The application is no longer restricted")
        next_status = "approved_pending_activation" if approve else "declined"
        tx.update(req_ref, {
            "status": next_status,
            "approvedMinutes": approved_minutes if approve else None,
            "decidedAt": firestore.SERVER_TIMESTAMP,
            "decidedBy": parent_uid,
            "decisionNotificationState": "pending",
        })
        if approve:
            tx.set(grant_ref, {
                "packageName": pkg,
                "appName": (authoritative_rule or {}).get("appName") or pkg,
                "requestId": request_id,
                "parentId": parent_uid,
                "childUid": profile["childAccountId"],
                "approvedMinutes": approved_minutes,
                "state": "pending_activation",
                "approvedAt": firestore.SERVER_TIMESTAMP,
                "activatedAt": None,
                "expiresAt": None,
            })
        return {"status": next_status, "approvedMinutes": approved_minutes if approve else None}

    # One transaction keeps the pending->decided transition idempotent.
    return decide(db.transaction())


def activate_grant(*, child_uid: str, profile_id: str,
                   package_name: str) -> dict[str, Any]:
    db = get_firestore_client()
    profile = _paired_profile(db, profile_id)
    if profile["childAccountId"] != child_uid:
        raise ChatAccessError("Only the paired child can activate this grant")
    if not package_name or "/" in package_name:
        raise ChatAccessError("Invalid package")
    ref = db.collection("child_profiles").document(profile_id).collection(
        "temporary_access_grants").document(package_name)
    now = dt.datetime.now(UTC)

    @transactional
    def activate(tx: Any) -> dict[str, Any]:
        snap = ref.get(transaction=tx)
        if not snap.exists:
            raise ChatAccessError("Grant not found")
        grant = snap.to_dict() or {}
        if grant.get("childUid") != child_uid:
            raise ChatAccessError("Grant owner mismatch")
        if grant.get("state") == "active":
            return {"status": "active", "expiresAt": grant.get("expiresAt")}
        if grant.get("state") != "pending_activation":
            raise ChatAccessError("Grant is not awaiting activation")
        minutes = grant.get("approvedMinutes")
        if not isinstance(minutes, int) or not 1 <= minutes <= MAX_APPROVED_MINUTES:
            raise ChatAccessError("Invalid approved duration")
        expiry = now + dt.timedelta(minutes=minutes)
        tx.update(ref, {"state": "active", "activatedAt": now, "expiresAt": expiry})
        request_id = grant.get("requestId")
        if isinstance(request_id, str) and request_id:
            request_ref = db.collection("child_profiles").document(profile_id).collection(
                "access_requests").document(request_id)
            tx.update(request_ref, {"status": "active", "activatedAt": now,
                                    "expiresAt": expiry})
        return {"status": "active", "expiresAt": expiry}

    return activate(db.transaction())


def _deliver(db: Any, uid: str, *, title: str, body: str, event_id: str,
             profile_id: str) -> str:
    account = db.collection("users").document(uid).get().to_dict() or {}
    token = account.get("fcmToken") or account.get("limitNotificationToken")
    if not token:
        return "no_token"
    try:
        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token,
            data={"type": "parent_child_chat", "eventId": event_id,
                  "childProfileId": profile_id},
            android=messaging.AndroidConfig(priority="high"),
        ))
        return "sent"
    except messaging.UnregisteredError:
        return "unregistered"
    except Exception:
        return "failed"


def sweep_chat_notifications(*, max_profiles: int = 200) -> dict[str, int]:
    """Best-effort at-most-once dispatch. Run from trusted scheduled worker.

    Claim on a server-authored transaction BEFORE FCM submission, so a repeated
    sweep doesn't intentionally deliver the same event twice. A crash after
    claiming can lose a push; messages/requests remain in persistent inbox.
    """
    db = get_firestore_client()
    result = {"scannedProfiles": 0, "claimed": 0, "sent": 0}

    def claim(ref: Any, field: str) -> bool:
        @transactional
        def claim_one(tx: Any) -> bool:
            snap = ref.get(transaction=tx)
            if not snap.exists or (snap.to_dict() or {}).get(field) != "pending":
                return False
            tx.update(ref, {field: "claimed", field + "ClaimedAt": firestore.SERVER_TIMESTAMP})
            return True
        return claim_one(db.transaction())

    for profile_doc in db.collection("child_profiles").limit(max_profiles).stream():
        profile = profile_doc.to_dict() or {}
        parent_uid, child_uid = profile.get("parentId"), profile.get("childAccountId")
        if not parent_uid or not child_uid:
            continue
        result["scannedProfiles"] += 1
        for msg in profile_doc.reference.collection("chat_messages").where(
                "notificationState", "==", "pending").limit(50).stream():
            data = msg.to_dict() or {}
            sender = data.get("senderId")
            if sender not in (parent_uid, child_uid) or not claim(msg.reference, "notificationState"):
                continue
            result["claimed"] += 1
            target = child_uid if sender == parent_uid else parent_uid
            status = _deliver(db, target, title="New WellScreen message",
                              body=str(data.get("body", ""))[:110],
                              event_id=msg.id, profile_id=profile_doc.id)
            # A missing token means no send was even attempted. Retry when a
            # device registers; other outcomes are not blindly retried.
            msg.reference.update({"notificationState":
                                  "pending" if status == "no_token" else status})
            if status == "sent":
                result["sent"] += 1
        for req in profile_doc.reference.collection("access_requests").limit(100).stream():
            data = req.to_dict() or {}
            expires_at = data.get("expiresAt")
            if (data.get("status") == "active" and isinstance(expires_at, dt.datetime)
                    and expires_at <= dt.datetime.now(UTC)):
                req.reference.update({"status": "expired"})
                grant_ref = profile_doc.reference.collection("temporary_access_grants").document(
                    str(data.get("packageName", "")))
                grant_snap = grant_ref.get()
                if grant_snap.exists and (grant_snap.to_dict() or {}).get("requestId") == req.id:
                    grant_ref.update({"state": "expired"})
            if data.get("notificationState") == "pending" and claim(req.reference, "notificationState"):
                result["claimed"] += 1
                status = _deliver(db, parent_uid, title="New app access request",
                                  body=f"Request: {data.get('appName', 'an app')} for {data.get('requestedMinutes', '?')} minutes",
                                  event_id="request_" + req.id, profile_id=profile_doc.id)
                req.reference.update({"notificationState":
                                      "pending" if status == "no_token" else status})
                if status == "sent":
                    result["sent"] += 1
            if data.get("decisionNotificationState") == "pending" and claim(req.reference, "decisionNotificationState"):
                result["claimed"] += 1
                status_name = data.get("status")
                title = "App access approved" if status_name in ("approved_pending_activation", "active") else "App access declined"
                body = f"{data.get('appName', 'App')}: {data.get('approvedMinutes')} minutes approved" if status_name in ("approved_pending_activation", "active") else f"{data.get('appName', 'App')} was declined"
                status = _deliver(db, child_uid, title=title, body=body,
                                  event_id="decision_" + req.id, profile_id=profile_doc.id)
                req.reference.update({"decisionNotificationState":
                                      "pending" if status == "no_token" else status})
                if status == "sent":
                    result["sent"] += 1
    return result
