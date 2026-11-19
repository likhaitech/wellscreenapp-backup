"""Task 7: one alert to the guardian when blocking (Accessibility) is off.

off -> one alert; still off -> no duplicate; back on then off -> new alert;
unknown status and unpaired profiles -> nothing. No live Firebase.
"""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app.services import monitoring_alerts_service as svc


@pytest.fixture
def env(monkeypatch):
    clock = [datetime(2026, 11, 20, 2, tzinfo=timezone.utc)]
    profile = {
        "parentId": "parent-1",
        "childAccountId": "child-1",
        "childDisplayName": "Mika",
        "pairingStatus": "connected",
        "lastSeenAt": clock[0],
    }
    records = {}

    def alert_document(alert_id):
        ref = Mock()

        def create(data):
            if alert_id in records:
                raise svc.AlreadyExists("duplicate")
            records[alert_id] = dict(data)

        ref.create.side_effect = create
        ref.update.side_effect = lambda data: records[alert_id].update(data)
        return ref

    alerts = Mock()
    alerts.document.side_effect = alert_document
    profile_ref = Mock()
    profile_ref.collection.return_value = alerts
    profile_ref.update.side_effect = lambda data: profile.update(data)
    snapshot = SimpleNamespace(id="profile-1", to_dict=lambda: dict(profile),
                               reference=profile_ref)
    profiles = Mock()
    profiles.document.return_value = profile_ref
    profiles.where.return_value.stream.side_effect = lambda: (
        [snapshot] if profile["pairingStatus"] == "connected" else [])
    db = Mock()
    db.collection.return_value = profiles

    push = Mock(return_value={"status": "sent", "message_id": "m"})
    monkeypatch.setattr(svc, "get_firestore_client", lambda: db)
    monkeypatch.setattr(svc, "_utcnow", lambda: clock[0])
    monkeypatch.setattr(svc, "send_alert_notification", push)
    monkeypatch.setattr(svc, "_send_sms", Mock(return_value={"status": "accepted"}))
    return SimpleNamespace(clock=clock, profile=profile, records=records, push=push)


def _off(env, minutes_ago=1):
    env.profile["accessibilityEnabled"] = False
    env.profile["accessibilityCheckedAt"] = env.clock[0] - timedelta(minutes=minutes_ago)


def _kinds(env):
    return [r["kind"] for r in env.records.values()]


def test_off_sends_one_alert(env):
    _off(env)

    result = svc.sweep_missing_heartbeats()

    assert _kinds(env) == ["accessibility_disabled"]
    assert result["newAlerts"] == 1
    env.push.assert_called_once()
    record = next(iter(env.records.values()))
    assert "Blocking was turned off" in record["title"]
    assert record["parentId"] == "parent-1"
    assert env.profile["accessibilityOffAlertedAt"] == env.clock[0]


def test_still_off_on_next_sweep_is_not_repeated(env):
    _off(env)
    svc.sweep_missing_heartbeats()
    env.clock[0] += timedelta(minutes=5)
    _off(env)  # a newer heartbeat that still says off

    svc.sweep_missing_heartbeats()

    assert _kinds(env) == ["accessibility_disabled"]
    assert env.push.call_count == 1


def test_back_on_then_off_again_alerts_again(env):
    _off(env)
    svc.sweep_missing_heartbeats()

    env.clock[0] += timedelta(minutes=5)
    env.profile["accessibilityEnabled"] = True
    env.profile["accessibilityCheckedAt"] = env.clock[0]
    svc.sweep_missing_heartbeats()
    assert env.profile["accessibilityOffAlertedAt"] is None

    env.clock[0] += timedelta(minutes=5)
    _off(env, minutes_ago=0)
    svc.sweep_missing_heartbeats()

    assert _kinds(env) == ["accessibility_disabled", "accessibility_disabled"]


def test_on_or_unknown_sends_nothing(env):
    env.profile["accessibilityEnabled"] = True
    svc.sweep_missing_heartbeats()
    env.profile.pop("accessibilityEnabled")
    svc.sweep_missing_heartbeats()

    assert env.records == {}
    env.push.assert_not_called()


def test_unpaired_profile_is_ignored(env):
    _off(env)
    env.profile["pairingStatus"] = "unpaired"

    svc.sweep_missing_heartbeats()

    assert env.records == {}
    env.push.assert_not_called()
