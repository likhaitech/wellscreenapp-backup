
from app.services import monitoring_alerts_service as alerts

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, pair_child, system  # noqa: F401

# What the child phone's pattern detection sends when it sees use between
# 10 PM and 5 AM (CriticalEventJournal.kt noteForegroundUse).
LATE_NIGHT = {"type": "late_night_usage", "eventId": "lateusage_20261122",
              "timestampMs": NOW_MS, "subject": "device_night_use", "label": "YouTube at 23:00"}


def test_int_006(system):
    def body() -> str:
        profile_id = pair_child(system)

        # Module 1 -> Module 2: the detected pattern is sent to the server.
        reply = alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id,
                                           events=[LATE_NIGHT])
        assert reply["acceptedEventIds"] == ["lateusage_20261122"]

        saved = guardian_alerts(system, profile_id)
        assert len(saved) == 1 and saved[0]["title"] == "Late-night device usage"
        assert "YouTube at 23:00" in saved[0]["body"]
        assert system.pushes[0]["parent_uid"] == GUARDIAN
        assert system.pushes[0]["data"]["alertType"] == "late_night_usage"

        # The same pattern sent again (next sync) does not alert twice.
        alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id, events=[LATE_NIGHT])
        assert len(guardian_alerts(system, profile_id)) == 1 and len(system.pushes) == 1
        return (f"Late-night use was sent by the child phone and the guardian received the "
                f"alert \"{saved[0]['title']}\": {saved[0]['body']} (sent once, not repeated "
                "on the next sync)")

    run_case(
        "INT-006",
        file="backend/tests/integration_cases/test_int_006.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description="Detect a usage concern that reaches a configured threshold (Pattern Detection -> Alerts and Communication).",
        expected="The guardian receives an alert notification describing the detected usage concern.",
        body=body,
    )
