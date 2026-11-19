"""Task 6: Device Admin alerts also leave an in-app record.

POST /alerts/notify with device_admin_disable_attempt or
device_admin_disabled saves one document in
child_profiles/{profileId}/monitoring_alerts, even when the push fails.
Other alert types never do. No live Firebase project is touched.
"""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import Mock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import device_admin_alert_service as svc
from app.services.notification_service import NoDeviceTokenError, NotAuthorizedError
from app.services.user_auth_service import require_user

client = TestClient(app)
TS = 1_795_000_000_000


@pytest.fixture
def env(monkeypatch):
    profile = {"parentId": "parent-1", "childAccountId": "child-1"}
    records: dict[str, dict] = {}

    def alert_document(alert_id):
        ref = Mock()

        def create(data):
            if alert_id in records:
                raise svc.AlreadyExists("duplicate")
            records[alert_id] = dict(data)

        ref.create.side_effect = create
        return ref

    alerts = Mock()
    alerts.document.side_effect = alert_document
    profile_ref = Mock()
    profile_ref.collection.return_value = alerts
    profile_ref.get.side_effect = lambda: SimpleNamespace(to_dict=lambda: dict(profile))
    profiles = Mock()
    profiles.document.return_value = profile_ref
    db = Mock()
    db.collection.return_value = profiles

    monkeypatch.setattr(svc, "get_firestore_client", lambda: db)
    app.dependency_overrides[require_user] = lambda: {"uid": "child-1"}
    yield SimpleNamespace(profile=profile, records=records, profiles=profiles)
    app.dependency_overrides.pop(require_user, None)


def _post(alert_type: str, *, push=None, data=None):
    body = {
        "parent_uid": "parent-1",
        "title": "t",
        "body": "b",
        "alert_type": alert_type,
        "data": data if data is not None else {"childProfileId": "profile-1", "timestampMs": TS},
    }
    send = push or Mock(return_value={"status": "sent", "message_id": "m1", "error": None})
    with patch("app.routes.alerts.send_alert_notification", send):
        return client.post("/alerts/notify", json=body,
                           headers={"Authorization": "Bearer test"})


@pytest.mark.parametrize("alert_type,severity", [
    ("device_admin_disable_attempt", "warning"),
    ("device_admin_disabled", "danger"),
])
def test_device_admin_alert_creates_record(env, alert_type, severity):
    response = _post(alert_type)

    assert response.status_code == 200
    assert response.json()["status"] == "sent"
    record = env.records[f"{alert_type}_{TS}"]
    assert record["kind"] == alert_type
    assert record["severity"] == severity
    assert record["parentId"] == "parent-1"
    assert record["pushStatus"] == "sent"
    assert record["title"] and record["body"]


def test_attempt_and_disabled_messages_are_plain(env):
    _post("device_admin_disable_attempt")
    _post("device_admin_disabled")
    bodies = {r["kind"]: r["body"] for r in env.records.values()}
    assert bodies["device_admin_disable_attempt"] == (
        "Your child tried to turn off uninstall protection.")
    assert "can now be uninstalled" in bodies["device_admin_disabled"]


@pytest.mark.parametrize("alert_type", ["usage_limit", "gps_location_stale", "unhealthy_usage_pattern"])
def test_other_alert_types_create_no_record(env, alert_type):
    response = _post(alert_type)

    assert response.status_code == 200
    assert env.records == {}


def test_record_saved_when_parent_has_no_device_token(env):
    response = _post("device_admin_disabled",
                     push=Mock(side_effect=NoDeviceTokenError("no token")))

    assert response.status_code == 200
    assert response.json()["status"] == "failed"
    assert env.records[f"device_admin_disabled_{TS}"]["pushStatus"] == "failed"


def test_record_saved_when_push_crashes(env):
    response = _post("device_admin_disabled",
                     push=Mock(side_effect=RuntimeError("fcm down")))

    assert response.status_code == 500
    assert env.records[f"device_admin_disabled_{TS}"]["pushStatus"] == "failed"


def test_retry_of_same_event_is_not_duplicated(env):
    _post("device_admin_disabled")
    _post("device_admin_disabled")

    assert len(env.records) == 1


def test_not_authorized_caller_creates_no_record(env):
    response = _post("device_admin_disabled",
                     push=Mock(side_effect=NotAuthorizedError("nope")))

    assert response.status_code == 403
    assert env.records == {}


def test_profile_of_another_child_is_ignored(env):
    env.profile["childAccountId"] = "someone-else"

    _post("device_admin_disabled")

    assert env.records == {}


def test_profile_paired_to_another_parent_is_ignored(env):
    env.profile["parentId"] = "parent-2"

    _post("device_admin_disabled")

    assert env.records == {}


def test_missing_profile_id_is_ignored(env):
    _post("device_admin_disabled", data={"timestampMs": TS})

    assert env.records == {}
