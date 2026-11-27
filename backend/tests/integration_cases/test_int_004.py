
from app.models.alert import AlertNotifyRequest
from app.routes import alerts as alerts_route

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, NOW_MS, guardian_alerts, pair_child, system  # noqa: F401


def test_int_004(system, monkeypatch):
    sent = []
    monkeypatch.setattr(alerts_route, "send_alert_notification",
                        lambda **kw: sent.append(kw) or {"status": "sent", "message_id": "push-1"})

    def body() -> str:

        profile_id = pair_child(system)

        payload = AlertNotifyRequest(
            parent_uid=GUARDIAN, alert_type="device_admin_disabled",
            title="WellScreen uninstall protection disabled",
            body="Device Admin protection has been disabled on your child's device.",
            data={"childProfileId": profile_id, "timestampMs": NOW_MS},
        )
        reply = alerts_route.notify(payload, current_user={"uid": CHILD})

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
