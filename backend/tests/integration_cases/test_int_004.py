"""INT-004 - Device Pairing and Permission Setup Module -> Alerts and Communication Module.
Child turns off uninstall protection; the guardian is alerted.
Run (from backend): python -m pytest tests/integration_cases/test_int_004.py -s -q -p no:anyio
"""
from app.models.alert import AlertNotifyRequest
from app.routes import alerts as alerts_route

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, pair_child, system  # noqa: F401


def test_int_004(system, monkeypatch):
    sent = []
    monkeypatch.setattr(alerts_route, "send_alert_notification",
                        lambda **kw: sent.append(kw) or {"status": "sent", "message_id": "push-1"})

    def body() -> str:
        # Module 1 - Device Pairing and Permission Setup: paired phone with
        # uninstall protection (Device Administrator) on.
        profile_id = pair_child(system)

        # The child turns it off; WellScreenDeviceAdminReceiver.kt posts this
        # to POST /alerts/notify (alertType "device_admin_disabled").
        payload = AlertNotifyRequest(
            parent_uid=GUARDIAN, alert_type="device_admin_disabled",
            title="WellScreen uninstall protection disabled",
            body="Device Admin protection has been disabled on your child's device.",
            data={"childProfileId": profile_id, "timestampMs": NOW_MS},
        )
        reply = alerts_route.notify(payload, current_user={"uid": CHILD})

        # Module 2 - Alerts and Communication: push to the guardian + an
        # entry in the guardian's Notifications.
        assert reply.status == "sent"
        assert sent[0]["parent_uid"] == GUARDIAN
        saved = guardian_alerts(system, profile_id)
        assert len(saved) == 1
        assert saved[0]["title"] == "Uninstall protection turned off"
        assert saved[0]["severity"] == "danger"
        return ("The paired child turned off uninstall protection: the guardian received "
                "a push and the Notifications entry \"Uninstall protection turned off\"")

    run_case(
        "INT-004",
        file="backend/tests/integration_cases/test_int_004.py",
        code_tested="backend/app/routes/alerts.py + device_admin_alert_service.py",
        description="Child turns off WellScreen's uninstall protection (Device Pairing -> Alerts and Communication).",
        expected="The guardian receives an alert that uninstall protection was disabled.",
        body=body,
    )
