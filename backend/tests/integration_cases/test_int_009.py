
from app.services import monitoring_alerts_service as alerts

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, pair_child, system  # noqa: F401


REVIEW = {"type": "site_review_needed", "eventId": "review-casino-example-0001",
          "timestampMs": NOW_MS, "subject": "casino-example.com", "label": "casino-example.com"}


def test_int_009(system):
    def body() -> str:
        profile_id = pair_child(system)
        reply = alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id, events=[REVIEW])
        assert reply["acceptedEventIds"] == [REVIEW["eventId"]]
        saved = guardian_alerts(system, profile_id)
        assert len(saved) == 1 and saved[0]["title"] == "Review this website"
        assert "It was not blocked" in saved[0]["body"]

        assert saved[0]["details"]["subject"] == "casino-example.com"
        assert saved[0]["smsStatus"] == "not_requested"  # decided in the app, never by SMS
        assert system.pushes[0]["parent_uid"] == GUARDIAN
        return ("The guardian received \"Review this website\" for casino-example.com (not "
                "blocked, no SMS); the alert carries the site so Allow saves it as an allowed "
                "website (Allow tap and the site opening are on the emulator figure)")

    run_case(
        "INT-009",
        file="backend/tests/integration_cases/test_int_009.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description="Child opens a review-level site, age group 7-12 (Rule Management -> Alerts and Communication).",
        expected="The guardian receives “Review this website”; tapping Allow saves a website rule and the site opens on the child device.",
        body=body,
    )
