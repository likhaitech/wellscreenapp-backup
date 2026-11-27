
from app.services import monitoring_alerts_service as alerts

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, pair_child, system  # noqa: F401


BLOCKED_SITE = {"type": "restricted_content_attempt", "eventId": "a1b2c3d4-blocked-site-0001",
                "timestampMs": NOW_MS, "subject": "pornhub.com", "label": "pornhub.com"}


def test_int_008(system):
    def body() -> str:
        profile_id = pair_child(system)
        reply = alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id,
                                           events=[BLOCKED_SITE])
        assert reply["acceptedEventIds"] == [BLOCKED_SITE["eventId"]]
        saved = guardian_alerts(system, profile_id)
        assert len(saved) == 1
        assert saved[0]["title"] == "Restricted content access attempted"
        assert saved[0]["details"]["subject"] == "pornhub.com"
        assert system.pushes[0]["parent_uid"] == GUARDIAN
        return ("The blocked attempt on pornhub.com was logged and the guardian received "
                f"\"{saved[0]['title']}\": {saved[0]['body']}")

    run_case(
        "INT-008",
        file="backend/tests/integration_cases/test_int_008.py",
        code_tested="backend/app/services/monitoring_alerts_service.py",
        description="Child attempts to open a website in a restricted harmful category (Rule Management -> Alerts and Communication).",
        expected="Access to the website is restricted, the attempt is logged, and the guardian is alerted.",
        body=body,
    )
