"""INT-003 - Device Pairing and Permission Setup Module -> Usage Monitoring Module.
Pair the child device; it appears under the guardian and its usage reports are accepted.
Run (from backend): python -m pytest tests/integration_cases/test_int_003.py -s -q -p no:anyio
"""
import pytest

from app.services import monitoring_alerts_service as alerts
from app.services import pairing_service as pairing

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, system  # noqa: F401

# Exactly what the child app sends after a usage sync when the 2-hour goal is
# reached (lib/services/monitoring_usage_alert_service.dart, buildEvents).
USAGE_EVENT = {"type": "usage_warning_threshold", "eventId": "usage2h_20261122",
               "timestampMs": NOW_MS, "subject": "Device usage", "label": "2 hours today"}


def test_int_003(system):
    db = system.db

    def body() -> str:
        made = pairing.generate_pairing_code(parent_uid=GUARDIAN, child_name="Ana")
        profile_id = made["childProfileId"]

        # Before pairing, the server does not take usage from this phone.
        with pytest.raises(PermissionError):
            alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id,
                                       events=[USAGE_EVENT])

        # Module 1 - Device Pairing: the child types the 6-digit code.
        assert pairing.redeem_pairing_code(child_uid=CHILD, code=made["code"])["status"] == "connected"
        assert db.docs[f"child_profiles/{profile_id}"]["parentId"] == GUARDIAN
        assert db.docs[f"users/{CHILD}"]["pairedParentId"] == GUARDIAN

        # Module 2 - Usage Monitoring: the paired phone's usage report is accepted.
        reply = alerts.accept_child_events(child_uid=CHILD, profile_id=profile_id,
                                           events=[USAGE_EVENT])
        assert reply["acceptedEventIds"] == ["usage2h_20261122"]
        saved = guardian_alerts(system, profile_id)
        assert [a["title"] for a in saved] == ["Daily screen-time goal reached"]
        return ("Before pairing the phone's usage was refused; after pairing with the "
                "code the device appears under the guardian and its usage report (2 hours "
                "today) was accepted and recorded for the guardian")

    run_case(
        "INT-003",
        file="backend/tests/integration_cases/test_int_003.py",
        code_tested="backend/app/services/pairing_service.py + monitoring_alerts_service.py",
        description="Pair the child device using the QR code or six-digit pairing code (Device Pairing -> Usage Monitoring).",
        expected="The child device appears under the guardian account and begins recording usage data.",
        body=body,
    )
