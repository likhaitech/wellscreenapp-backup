"""WellScreen's 90-day server-side retention job.

Read-only by default. Run from backend/:
    python -m app.services.data_cleanup_service

Actual removal requires --apply and the exact expected Firebase project ID.
This module does not register an HTTP endpoint or schedule itself.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from typing import Any, Iterator

from google.api_core.exceptions import FailedPrecondition, NotFound
from google.cloud.firestore_v1.base_query import FieldFilter

from .firebase_service import get_firestore_client


RETENTION_DAYS = 90
PAGE_SIZE = 200
PROFILE_LOG_FIELDS = (
    "browsingLog",
    "restrictionLog",
    "syncLog",
    "smsAlertLog",
)
RECORD_TYPES = ("system_logs", "chat_messages", *PROFILE_LOG_FIELDS)


def _new_counts() -> dict[str, int]:
    return {name: 0 for name in RECORD_TYPES}


def _expired_timestamp(value: Any, cutoff: dt.datetime) -> bool:
    # Only genuine, timezone-aware Firestore timestamps are eligible.
    # Missing, naive or malformed dates must not cause deletion.
    return (
        isinstance(value, dt.datetime)
        and value.utcoffset() is not None
        and value < cutoff
    )


def _profile_updates(
    profile: dict[str, Any], cutoff_ms: int
) -> tuple[dict[str, list[Any]], dict[str, int]]:
    updates: dict[str, list[Any]] = {}
    removed: dict[str, int] = {}
    for field in PROFILE_LOG_FIELDS:
        entries = profile.get(field)
        if not isinstance(entries, list):
            continue
        kept = []
        for entry in entries:
            stamp = entry.get("timestampMs") if isinstance(entry, dict) else None
            # Reject booleans, negative values, and non-integer timestamps.
            # Preserve unknown entries instead of guessing their age.
            if type(stamp) is int and 0 < stamp < cutoff_ms:
                continue
            kept.append(entry)
        if len(kept) != len(entries):
            updates[field] = kept
            removed[field] = len(entries) - len(kept)
    return updates, removed


def _pages(query: Any) -> Iterator[Any]:
    """Use bounded ordered pages, including the final partial page."""
    cursor = None
    while True:
        page_query = query.limit(PAGE_SIZE)
        if cursor is not None:
            page_query = page_query.start_after(cursor)
        page = list(page_query.stream())
        if not page:
            return
        yield from page
        if len(page) < PAGE_SIZE:
            return
        cursor = page[-1]


def _old_documents(collection: Any, field: str, cutoff: dt.datetime) -> Iterator[Any]:
    query = collection.where(filter=FieldFilter(field, "<", cutoff)).order_by(field)
    # Explicit document-ID ordering makes equal timestamps page correctly.
    query = query.order_by("__name__")
    for snapshot in _pages(query):
        if _expired_timestamp((snapshot.to_dict() or {}).get(field), cutoff):
            yield snapshot


def _write_if_unchanged(
    db: Any, snapshot: Any, updates: dict[str, Any] | None = None
) -> bool:
    """Do not overwrite concurrent profile syncs or delete changed documents."""
    if snapshot.update_time is None:
        return False
    option = db.write_option(last_update_time=snapshot.update_time)
    try:
        if updates is None:
            snapshot.reference.delete(option=option)
        else:
            snapshot.reference.update(updates, option=option)
        return True
    except (FailedPrecondition, NotFound):
        # Another client changed or removed this document after we read it.
        # A future cleanup pass can reconsider its latest contents.
        return False


def cleanup_old_data(
    *,
    dry_run: bool = True,
    expected_project: str | None = None,
    now: dt.datetime | None = None,
    db: Any = None,
) -> dict[str, Any]:
    """Report or delete only explicitly approved history older than 90 days.

    Never deletes child profile documents, accounts, restrictions, grants,
    access requests, notifications or monitoring-alert deduplication records.
    Unknown timestamps are retained. Non-conflict Firestore errors propagate
    so a failed run cannot be reported as a successful cleanup.
    """
    if not isinstance(dry_run, bool):
        raise TypeError("dry_run must be a bool")
    if not dry_run and not expected_project:
        raise ValueError("An expected Firebase project ID is required to delete data")

    now = dt.datetime.now(dt.timezone.utc) if now is None else now
    if now.utcoffset() is None:
        raise ValueError("now must be timezone-aware")
    cutoff = now.astimezone(dt.timezone.utc) - dt.timedelta(days=RETENTION_DAYS)
    cutoff_ms = int(cutoff.timestamp() * 1000)

    if db is None:
        db = get_firestore_client()
    project = db.project
    if expected_project is not None and project != expected_project:
        raise ValueError("Firebase project does not match the expected project ID")

    report: dict[str, Any] = {
        "project_id": project,
        "dry_run": dry_run,
        "retention_days": RETENTION_DAYS,
        "cutoff_utc": cutoff.isoformat(),
        "profiles_scanned": 0,
        "candidates": _new_counts(),
        "removed": _new_counts(),
        "concurrent_changes_skipped": 0,
    }

    def clean_documents(collection: Any, timestamp_field: str, kind: str) -> None:
        for snapshot in _old_documents(collection, timestamp_field, cutoff):
            report["candidates"][kind] += 1
            if dry_run:
                continue
            if _write_if_unchanged(db, snapshot):
                report["removed"][kind] += 1
            else:
                report["concurrent_changes_skipped"] += 1

    clean_documents(db.collection("system_logs"), "timestamp", "system_logs")

    for profile in _pages(db.collection("child_profiles").order_by("__name__")):
        report["profiles_scanned"] += 1
        updates, counts = _profile_updates(profile.to_dict() or {}, cutoff_ms)
        for field, count in counts.items():
            report["candidates"][field] += count
        if updates and not dry_run:
            if _write_if_unchanged(db, profile, updates):
                for field, count in counts.items():
                    report["removed"][field] += count
            else:
                report["concurrent_changes_skipped"] += 1

        clean_documents(
            profile.reference.collection("chat_messages"),
            "createdAt",
            "chat_messages",
        )

    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="WellScreen 90-day data retention")
    parser.add_argument("--project-id", help="Expected Firebase project ID")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Preview without writes (default)")
    mode.add_argument("--apply", action="store_true", help="Actually remove expired records")
    args = parser.parse_args()
    if args.apply and not args.project_id:
        parser.error("--apply requires --project-id")

    report = cleanup_old_data(dry_run=not args.apply, expected_project=args.project_id)
    # Counts only: never print chat contents, browsing URLs or account data.
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
