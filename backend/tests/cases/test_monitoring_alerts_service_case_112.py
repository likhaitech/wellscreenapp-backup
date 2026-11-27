"""CASE-112 - Alerts and Communication / Location Tracking.
Run (from backend): python -m pytest tests/cases/test_monitoring_alerts_service_case_112.py -s -q
"""
from datetime import timedelta  # noqa: F401  (used by some cases)

from app.services import monitoring_alerts_service as svc

from .alert_fixture import NOW, alerts_env  # noqa: F401
from .case_report import run_case


def test_case_112(alerts_env):
    env = alerts_env

    def body() -> str:
        env.profile["lastSeenAt"] = NOW - timedelta(hours=3)
        svc.sweep_missing_heartbeats()
        alert = next(a for a in env.records.values() if a["kind"] == "no_recent_connection")
        assert "has not reported recently" in alert["body"]
        return (f"Last seen 3 hours ago: the guardian got \"{alert['title']}\" "
                f"saying the device has not reported recently (push {alert['pushStatus']}, "
                f"SMS {alert['smsStatus']})")

    run_case(
        "CASE-112",
        file="backend/tests/cases/test_monitoring_alerts_service_case_112.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description='Child device stops reporting for a long time.',
        expected='The guardian receives an alert that the child device has not checked in.',
        body=body,
    )
