"""CASE-109 - Alerts and Communication / Location Tracking.
Run (from backend): python -m pytest tests/cases/test_monitoring_alerts_service_case_109.py -s -q
"""
from datetime import timedelta  # noqa: F401  (used by some cases)

from app.services import monitoring_alerts_service as svc

from .alert_fixture import NOW, alerts_env  # noqa: F401
from .case_report import run_case


def test_case_109(alerts_env):
    env = alerts_env

    def body() -> str:
        ms = int(NOW.timestamp() * 1000)
        result = svc.accept_child_events(child_uid="child-1", profile_id="profile-1", events=[
            {"type": "usage_warning_threshold", "eventId": "goal-reached-0001",
             "timestampMs": ms, "label": "2h 0m"}])
        assert result["acceptedEventIds"] == ["goal-reached-0001"]
        env.push.assert_called_once()
        sent = env.push.call_args.kwargs
        assert sent["parent_uid"] == "parent-1"
        assert sent["title"] == "Daily screen-time goal reached"
        return (f"The child's goal event was accepted and a push \"{sent['title']}\" "
                f"was sent to the guardian (push status: {env.records['child_goal-reached-0001']['pushStatus']})")

    run_case(
        "CASE-109",
        file="backend/tests/cases/test_monitoring_alerts_service_case_109.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description='Child reaches the daily goal while the guardian app is closed.',
        expected='A push notification arrives on the guardian device.',
        body=body,
    )
