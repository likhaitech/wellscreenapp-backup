"""What the administrator sees about the running system - counts only,
never a family's activity.

- Background jobs (monitoring check, chat notifications, data cleanup)
  record their last run in system_status/{job}; runs that did something,
  and every failure, are also written to System logs.
- The monitoring check (every 5 minutes) keeps today's totals of active
  guardians and active child devices in system_stats/{YYYY-MM-DD}
  (Philippine date). The admin dashboard graph reads only these totals.

Active means: a child device checked in that day (child_profiles.lastSeenAt)
or a guardian opened the app that day (users.lastActiveAt).
"""
from __future__ import annotations

import datetime as dt
import logging
from typing import Any, Iterable
from zoneinfo import ZoneInfo

from firebase_admin import firestore

from .firebase_service import get_firestore_client
from .system_log_service import create_system_log

log = logging.getLogger(__name__)

MANILA = ZoneInfo("Asia/Manila")
JOBS = ("monitoring", "chat_notifications", "data_cleanup")


def manila_day(now: dt.datetime) -> str:
    return now.astimezone(MANILA).date().isoformat()


def start_of_manila_day(now: dt.datetime) -> dt.datetime:
    local = now.astimezone(MANILA)
    start = dt.datetime(local.year, local.month, local.day, tzinfo=MANILA)
    return start.astimezone(dt.timezone.utc)


def _as_utc(value: Any) -> dt.datetime | None:
    if isinstance(value, dt.datetime):
        return value if value.tzinfo else value.replace(tzinfo=dt.timezone.utc)
    return None


def active_since(values: Iterable[Any], since: dt.datetime) -> int:
    """How many timestamps are at or after `since`."""
    count = 0
    for value in values:
        moment = _as_utc(value)
        if moment is not None and moment >= since:
            count += 1
    return count


def record_job(
    job: str,
    *,
    ok: bool,
    summary: dict[str, Any],
    log_entry: bool,
    message: str = "",
    db: Any = None,
    write_log: Any = create_system_log,
) -> None:
    """Remember the job's last run; log it when it did something or failed.

    Never raises: a status write must not break the job it describes.
    """
    try:
        db = db or get_firestore_client()
        db.collection("system_status").document(job).set({
            "job": job,
            "ok": ok,
            "lastRunAt": firestore.SERVER_TIMESTAMP,
            "summary": summary,
        }, merge=True)
    except Exception as exc:  # pragma: no cover - logging only
        log.warning("Could not save %s status: %s", job, type(exc).__name__)
    if not (log_entry or not ok):
        return
    try:
        write_log(
            level="info" if ok else "error",
            action=f"{job}_{'completed' if ok else 'failed'}",
            message=message or (f"{job.replace('_', ' ').capitalize()} "
                                f"{'completed' if ok else 'failed'}"),
            details=summary,
        )
    except Exception as exc:  # pragma: no cover - logging only
        log.warning("Could not log %s: %s", job, type(exc).__name__)


def log_delivery_problem(
    *, alert_kind: str, push_status: str, sms_status: str,
    write_log: Any = create_system_log,
) -> None:
    """A guardian alert that did not go out normally. No names or IDs."""
    push_ok = push_status == "sent"
    sms_ok = sms_status == "accepted"
    if push_ok:
        return
    try:
        write_log(
            level="warning" if sms_ok else "error",
            action="alert_delivery_failed" if not sms_ok else "alert_push_failed",
            message=("Guardian alert sent by SMS only (push failed)" if sms_ok
                     else "Guardian alert could not be delivered"),
            details={"alertKind": alert_kind, "push": push_status, "sms": sms_status},
        )
    except Exception as exc:  # pragma: no cover - logging only
        log.warning("Could not log delivery problem: %s", type(exc).__name__)


def guardian_last_active(db: Any, since: dt.datetime) -> list[Any]:
    """lastActiveAt of guardian accounts active since `since` (single-field
    range query, so no composite index is needed; role checked here)."""
    values = []
    for doc in db.collection("users").where("lastActiveAt", ">=", since).stream():
        data = doc.to_dict() or {}
        if data.get("role") == "parent":
            values.append(data.get("lastActiveAt"))
    return values


def record_daily_activity(
    *, active_children: int, active_guardians: int, now: dt.datetime, db: Any = None,
) -> None:
    try:
        db = db or get_firestore_client()
        day = manila_day(now)
        db.collection("system_stats").document(day).set({
            "date": day,
            "activeChildren": active_children,
            "activeGuardians": active_guardians,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)
    except Exception as exc:  # pragma: no cover - logging only
        log.warning("Could not save daily activity: %s", type(exc).__name__)


def last_days(now: dt.datetime, days: int) -> list[str]:
    today = now.astimezone(MANILA).date()
    return [(today - dt.timedelta(days=offset)).isoformat()
            for offset in range(days - 1, -1, -1)]


def admin_overview(*, days: int = 7, now: dt.datetime | None = None,
                   db: Any = None) -> dict[str, Any]:
    """Daily active totals (oldest first, missing days = 0) and job status."""
    now = now or dt.datetime.now(dt.timezone.utc)
    db = db or get_firestore_client()
    dates = last_days(now, days)
    refs = [db.collection("system_stats").document(d) for d in dates]
    found: dict[str, dict[str, Any]] = {}
    for snap in db.get_all(refs):
        if snap.exists:
            found[snap.id] = snap.to_dict() or {}
    daily = [{
        "date": d,
        "activeGuardians": int(found.get(d, {}).get("activeGuardians") or 0),
        "activeChildren": int(found.get(d, {}).get("activeChildren") or 0),
        "recorded": d in found,
    } for d in dates]

    jobs: dict[str, Any] = {}
    for job in JOBS:
        snap = db.collection("system_status").document(job).get()
        if snap.exists:
            data = snap.to_dict() or {}
            last = _as_utc(data.get("lastRunAt"))
            jobs[job] = {
                "ok": bool(data.get("ok")),
                "lastRunAt": last.isoformat() if last else None,
                "summary": data.get("summary") or {},
            }
        else:
            jobs[job] = None
    return {"daily": daily, "jobs": jobs}


def refresh_daily_activity(*, now: dt.datetime | None = None, db: Any = None) -> dict[str, int] | None:
    """Recount today's active child devices and guardians. Never raises."""
    try:
        now = now or dt.datetime.now(dt.timezone.utc)
        db = db or get_firestore_client()
        since = start_of_manila_day(now)
        children = active_since(
            ((doc.to_dict() or {}).get("lastSeenAt") for doc in
             db.collection("child_profiles").where("lastSeenAt", ">=", since).stream()),
            since,
        )
        guardians = active_since(guardian_last_active(db, since), since)
        record_daily_activity(active_children=children, active_guardians=guardians,
                              now=now, db=db)
        return {"activeChildren": children, "activeGuardians": guardians}
    except Exception as exc:
        log.warning("Could not refresh daily activity: %s", type(exc).__name__)
        return None
