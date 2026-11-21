"""Admin dashboard counts: daily active totals and background job status.
Counts only; no family data is returned."""
from __future__ import annotations

import datetime as dt
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.services import system_activity_service as svc
from app.services.admin_auth_service import require_admin

UTC = dt.timezone.utc
client = TestClient(app)


def test_manila_day_boundary():
    # 16:30 UTC on the 20th is 00:30 on the 21st in Manila.
    now = dt.datetime(2026, 11, 20, 16, 30, tzinfo=UTC)
    assert svc.manila_day(now) == "2026-11-21"
    assert svc.start_of_manila_day(now) == dt.datetime(2026, 11, 20, 16, 0, tzinfo=UTC)


def test_active_since_counts_only_today():
    since = dt.datetime(2026, 11, 20, 16, 0, tzinfo=UTC)
    values = [
        dt.datetime(2026, 11, 20, 17, 0, tzinfo=UTC),   # today
        dt.datetime(2026, 11, 20, 15, 59, tzinfo=UTC),  # yesterday
        dt.datetime(2026, 11, 21, 1, 0),                # naive = UTC, today
        None, "bad",
    ]
    assert svc.active_since(values, since) == 2


def _doc(data):
    doc = MagicMock()
    doc.to_dict.return_value = data
    return doc


def test_refresh_daily_activity_counts_children_and_guardians():
    now = dt.datetime(2026, 11, 21, 2, 0, tzinfo=UTC)  # 10:00 Manila
    today = dt.datetime(2026, 11, 21, 1, 0, tzinfo=UTC)
    db = MagicMock()

    def collection(name):
        col = MagicMock()
        if name == "child_profiles":
            col.where.return_value.stream.return_value = [
                _doc({"lastSeenAt": today}), _doc({"lastSeenAt": today})]
        elif name == "users":
            col.where.return_value.stream.return_value = [
                _doc({"role": "parent", "lastActiveAt": today}),
                _doc({"role": "child", "lastActiveAt": today}),  # not a guardian
                _doc({"role": "admin", "lastActiveAt": today})]
        return col

    db.collection.side_effect = collection
    with patch.object(svc, "record_daily_activity") as record:
        assert svc.refresh_daily_activity(now=now, db=db) == {
            "activeChildren": 2, "activeGuardians": 1}
    assert record.call_args.kwargs["active_children"] == 2
    assert record.call_args.kwargs["active_guardians"] == 1


def test_refresh_daily_activity_never_raises():
    db = MagicMock()
    db.collection.side_effect = RuntimeError("down")
    assert svc.refresh_daily_activity(db=db) is None


def test_record_job_logs_only_when_it_did_something_or_failed():
    db = MagicMock()
    log = MagicMock()
    svc.record_job("monitoring", ok=True, summary={"newAlerts": 0},
                   log_entry=False, db=db, write_log=log)
    log.assert_not_called()
    db.collection.return_value.document.return_value.set.assert_called_once()

    svc.record_job("monitoring", ok=True, summary={"newAlerts": 2},
                   log_entry=True, message="Monitoring check sent 2 guardian alert(s)",
                   db=db, write_log=log)
    assert log.call_args.kwargs["action"] == "monitoring_completed"
    assert log.call_args.kwargs["level"] == "info"

    svc.record_job("data_cleanup", ok=False, summary={"error": "X"},
                   log_entry=False, db=db, write_log=log)
    assert log.call_args.kwargs["action"] == "data_cleanup_failed"
    assert log.call_args.kwargs["level"] == "error"


def test_delivery_problem_levels():
    log = MagicMock()
    svc.log_delivery_problem(alert_kind="no_recent_connection", push_status="sent",
                             sms_status="backup_not_needed", write_log=log)
    log.assert_not_called()
    svc.log_delivery_problem(alert_kind="no_recent_connection", push_status="failed",
                             sms_status="accepted", write_log=log)
    assert log.call_args.kwargs["level"] == "warning"
    svc.log_delivery_problem(alert_kind="no_recent_connection", push_status="failed",
                             sms_status="not_enabled", write_log=log)
    assert log.call_args.kwargs["level"] == "error"
    assert log.call_args.kwargs["action"] == "alert_delivery_failed"
    # No names, profile IDs or messages - only the kind and the outcomes.
    assert set(log.call_args.kwargs["details"]) == {"alertKind", "push", "sms"}


def test_admin_overview_fills_missing_days_and_reads_jobs():
    now = dt.datetime(2026, 11, 21, 2, 0, tzinfo=UTC)
    db = MagicMock()
    stats = MagicMock(exists=True, id="2026-11-21")
    stats.to_dict.return_value = {"activeGuardians": 3, "activeChildren": 5}
    db.get_all.return_value = [stats]
    job = MagicMock(exists=True)
    job.to_dict.return_value = {"ok": True, "lastRunAt": now, "summary": {"scanned": 4}}
    db.collection.return_value.document.return_value.get.return_value = job

    result = svc.admin_overview(days=3, now=now, db=db)
    assert [d["date"] for d in result["daily"]] == ["2026-11-19", "2026-11-20", "2026-11-21"]
    assert result["daily"][0] == {"date": "2026-11-19", "activeGuardians": 0,
                                  "activeChildren": 0, "recorded": False}
    assert result["daily"][2]["activeChildren"] == 5
    assert result["jobs"]["monitoring"]["ok"] is True


def test_overview_route_requires_admin_and_returns_counts():
    assert client.get("/admin/overview/").status_code == 401
    app.dependency_overrides[require_admin] = lambda: {"uid": "a", "admin": True}
    try:
        with patch("app.routes.admin_overview.admin_overview",
                   return_value={"daily": [], "jobs": {}}) as overview, \
             patch("app.routes.admin_overview.refresh_daily_activity") as refresh:
            r = client.get("/admin/overview/?days=30")
            assert client.get("/admin/overview/?days=31").status_code == 422
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r.status_code == 200
    assert overview.call_args.kwargs["days"] == 30
    # Today is recounted on every request, so the dashboard is current.
    refresh.assert_called()
    assert set(r.json()) == {"daily", "jobs", "server"}
