"""CASE-122 - Alerts and Communication / Location Tracking.
Run (from backend): python -m pytest tests/cases/test_monitoring_alerts_service_case_122.py -s -q
"""
from datetime import timedelta  # noqa: F401  (used by some cases)

from app.services import monitoring_alerts_service as svc

from .alert_fixture import NOW, alerts_env  # noqa: F401
from .case_report import run_case


def test_case_122(alerts_env):
    env = alerts_env

    def body() -> str:
        env.profile["locationUpdatedAt"] = NOW - timedelta(hours=2)
        svc.sweep_missing_heartbeats()
        alert = next(a for a in env.records.values() if a["kind"] == "gps_location_stale")
        assert alert["title"] == "Child's location is outdated"
        return (f"Location 2 hours old: the guardian got \"{alert['title']}\" "
                f"(push {alert['pushStatus']})")

    run_case(
        "CASE-122",
        file="backend/tests/cases/test_monitoring_alerts_service_case_122.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description='Child location is not updated for a long time.',
        expected='The guardian receives an outdated location warning.',
        body=body,
    )
