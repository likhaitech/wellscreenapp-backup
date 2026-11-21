"""CASE-110 - Alerts and Communication / Location Tracking.
Run (from backend): python -m pytest tests/cases/test_monitoring_alerts_service_case_110.py -s -q
"""
from datetime import timedelta  # noqa: F401  (used by some cases)

from app.services import monitoring_alerts_service as svc

from .alert_fixture import NOW, alerts_env  # noqa: F401
from .case_report import run_case


def test_case_110(alerts_env):
    env = alerts_env

    def body() -> str:
        env.profile["accessibilityEnabled"] = False
        env.profile["accessibilityCheckedAt"] = NOW
        svc.sweep_missing_heartbeats()
        alert = next(a for a in env.records.values() if a["kind"] == "accessibility_disabled")
        assert alert["title"] == "Blocking was turned off on your child's phone"
        env.push.assert_called_once()
        return (f"The heartbeat reported Accessibility off; the guardian got "
                f"\"{alert['title']}\" (push {alert['pushStatus']}), shown as Blocking is off")

    run_case(
        "CASE-110",
        file="backend/tests/cases/test_monitoring_alerts_service_case_110.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description='Child turns off the WellScreen Accessibility Service.',
        expected='The guardian sees “Blocking is off” and receives a protection alert.',
        body=body,
    )
