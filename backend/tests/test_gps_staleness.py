from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app.services import monitoring_alerts_service as svc


@pytest.fixture
def env(monkeypatch):
    clock = [datetime(2026, 11, 19, 12, tzinfo=timezone.utc)]

    profile = {
        "parentId": "parent-1",
        "childAccountId": "child-1",
        "childDisplayName": "Test Child",
        "pairingStatus": "connected",
        "lastSeenAt": clock[0],
    }

    records = {}
    child_account = {"fcmToken": "child-token"}
    child_push = Mock(return_value="child-message")
    profile_ref = Mock()
    alerts = Mock()

    def alert_document(alert_id):
        ref = Mock()

        def create(data):
            if alert_id in records:
                raise svc.AlreadyExists("Duplicate alert")
            records[alert_id] = dict(data)

        def update(data):
            records[alert_id].update(data)

        ref.get.side_effect = lambda **kwargs: SimpleNamespace(
            exists=alert_id in records,
            to_dict=lambda: dict(records.get(alert_id, {})),
        )
        ref.create.side_effect = create
        ref.update.side_effect = update
        return ref

    alerts.document.side_effect = alert_document
    profile_ref.collection.return_value = alerts
    profile_ref.get.side_effect = lambda **kwargs: SimpleNamespace(
        exists=True, to_dict=lambda: dict(profile),
    )
    profile_ref.update.side_effect = lambda data: profile.update(data)

    snapshot = SimpleNamespace(
        id="profile-1",
        to_dict=lambda: dict(profile),
        reference=profile_ref,
    )

    profiles = Mock()
    profiles.document.return_value = profile_ref
    profiles.where.return_value.stream.side_effect = lambda: (
        [snapshot] if profile["pairingStatus"] == "connected" else []
    )

    db = Mock()
    users = Mock()
    users.document.return_value.get.return_value.to_dict.side_effect = (
        lambda: dict(child_account)
    )
    db.collection.side_effect = lambda name: users if name == "users" else profiles
    db.transaction.return_value.update.side_effect = lambda ref, data: ref.update(data)
    monkeypatch.setattr(svc, "transactional", lambda fn: fn)
    monkeypatch.setattr(svc.messaging, "send", child_push)

    push = Mock(return_value={
        "status": "sent",
        "message_id": "test-message",
    })

    sms = Mock(return_value={"status": "accepted"})

    monkeypatch.setattr(svc, "get_firestore_client", lambda: db)
    monkeypatch.setattr(svc, "_utcnow", lambda: clock[0])
    monkeypatch.setattr(svc, "send_alert_notification", push)
    monkeypatch.setattr(svc, "_send_sms", sms)

    return SimpleNamespace(
        clock=clock,
        profile=profile,
        records=records,
        push=push,
        sms=sms,
        child_account=child_account,
        child_push=child_push,
        users=users,
    )


@pytest.mark.parametrize("age_minutes", [0, 10, 59, 60, -10])
def test_recent_or_future_location_does_not_alert(env, age_minutes):
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(minutes=age_minutes)
    )

    svc.sweep_missing_heartbeats()

    assert env.records == {}
    env.push.assert_not_called()
    env.child_push.assert_not_called()


def test_missing_location_does_not_alert(env):
    svc.sweep_missing_heartbeats()

    assert env.records == {}
    env.push.assert_not_called()
    env.child_push.assert_not_called()


def test_stale_location_creates_history_and_push(env):
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(hours=2)
    )

    result = svc.sweep_missing_heartbeats()

    assert result["newAlerts"] == 1
    assert len(env.records) == 1

    alert = next(iter(env.records.values()))

    assert alert["kind"] == "gps_location_stale"
    assert alert["parentId"] == "parent-1"
    assert alert["pushStatus"] == "sent"
    assert alert["smsStatus"] == "not_requested"

    env.push.assert_called_once()
    assert env.push.call_args.kwargs["parent_uid"] == "parent-1"

    env.sms.assert_not_called()
    assert env.child_push.call_count == 1


def test_repeated_sweeps_do_not_duplicate_alerts(env):
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(hours=2)
    )

    svc.sweep_missing_heartbeats()
    svc.sweep_missing_heartbeats()

    assert len(env.records) == 1
    assert env.push.call_count == 1
    assert env.child_push.call_count == 1


def test_fresh_location_starts_new_alert_episode(env):
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(hours=2)
    )

    svc.sweep_missing_heartbeats()

    env.profile["locationUpdatedAt"] = env.clock[0]
    svc.sweep_missing_heartbeats()

    assert len(env.records) == 1

    env.clock[0] += timedelta(minutes=61)
    env.profile["lastSeenAt"] = env.clock[0]

    svc.sweep_missing_heartbeats()

    assert len(env.records) == 2
    assert env.push.call_count == 2
    assert env.child_push.call_count == 2


def test_failed_push_still_preserves_notification_history(env):
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(hours=2)
    )

    env.push.side_effect = RuntimeError("FCM unavailable")

    svc.sweep_missing_heartbeats()

    assert len(env.records) == 1
    alert = next(iter(env.records.values()))

    assert alert["kind"] == "gps_location_stale"
    assert alert["pushStatus"] == "failed"

    env.sms.assert_not_called()
    assert env.child_push.call_count == 1


def test_child_gps_push_has_correct_recipient_and_content(env):
    env.profile["locationUpdatedAt"] = env.clock[0] - timedelta(hours=2)
    svc.sweep_missing_heartbeats()
    env.users.document.assert_called_once_with("child-1")
    env.child_push.assert_called_once()
    msg = env.child_push.call_args.args[0]
    assert msg.token == "child-token"
    assert msg.notification.title == "Location Update Needed"
    assert "Your location is outdated" in msg.notification.body
    assert "Nov 19, 2026 06:00 PM PHT" in msg.notification.body
    assert msg.android.notification.channel_id == "wellscreen_location"
    assert msg.data["type"] == "gps_location_stale"
    assert msg.data["recipientUid"] == "child-1"
    assert msg.data["childProfileId"] == "profile-1"
    assert next(iter(env.records.values()))["childPushStatus"] == "sent"


def test_child_missing_token_can_retry_without_resending_parent(env):
    env.profile["locationUpdatedAt"] = env.clock[0] - timedelta(hours=2)
    env.child_account.clear()
    svc.sweep_missing_heartbeats()
    env.child_push.assert_not_called()
    env.child_account["limitNotificationToken"] = "fallback-token"
    svc.sweep_missing_heartbeats()
    svc.sweep_missing_heartbeats()
    env.push.assert_called_once()
    env.child_push.assert_called_once()
    assert env.child_push.call_args.args[0].token == "fallback-token"


def test_child_push_failure_does_not_resend_guardian_or_child(env):
    env.profile["locationUpdatedAt"] = env.clock[0] - timedelta(hours=2)
    env.child_push.side_effect = RuntimeError("FCM unavailable")
    svc.sweep_missing_heartbeats()
    svc.sweep_missing_heartbeats()
    env.push.assert_called_once()
    env.child_push.assert_called_once()
    alert = next(iter(env.records.values()))
    assert alert["pushStatus"] == "sent"
    assert alert["childPushStatus"] == "failed"


def test_unpaired_child_does_not_generate_alert(env):
    env.profile["pairingStatus"] = "not_paired"
    env.profile["locationUpdatedAt"] = (
        env.clock[0] - timedelta(hours=3)
    )

    svc.sweep_missing_heartbeats()

    env.child_push.assert_not_called()
    assert env.records == {}
    env.push.assert_not_called()