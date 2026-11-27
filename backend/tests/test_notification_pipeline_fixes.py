"""Regression tests for the chat dispatch route, LOGGER bug, and monitoring wiring."""
from __future__ import annotations

import time
from types import SimpleNamespace
from unittest import mock

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import chat_access_service as cas
from app.services import monitoring_alerts_service as mas


class Doc:
    def __init__(self, store, path):
        self.store, self.path = store, path

    def get(self, transaction=None):
        d = self.store.get(self.path)
        return SimpleNamespace(exists=d is not None, to_dict=lambda: dict(d or {}), id=self.path.split("/")[-1])

    def update(self, data, *_a):
        self.store[self.path].update(data)

    def collection(self, name):
        return Col(self.store, f"{self.path}/{name}")


class Col:
    def __init__(self, store, path):
        self.store, self.path = store, path

    def document(self, doc_id):
        return Doc(self.store, f"{self.path}/{doc_id}")

    def order_by(self, field, direction="ASCENDING"):
        rows = [doc for doc in self.stream() if field in doc.to_dict()]
        rows.sort(key=lambda doc: doc.to_dict()[field], reverse=direction == "DESCENDING")
        return Query(rows)

    def where(self, *, filter):
        assert filter.op_string == "in"
        return Query([
            doc for doc in self.stream()
            if doc.to_dict().get(filter.field_path) in filter.value
        ])

    def stream(self, transaction=None):
        return [
            Doc(self.store, path).get()
            for path in self.store
            if path.rpartition("/")[0] == self.path
        ]


class Query:
    def __init__(self, rows):
        self.rows = rows

    def limit(self, count):
        return Query(self.rows[:count])

    def stream(self, transaction=None):
        return iter(self.rows)


class Tx:
    def __init__(self, store):
        self.store = store

    def update(self, ref, data):
        ref.update(data)

    def set(self, ref, data):
        self.store[ref.path] = dict(data)


class FakeDb:
    def __init__(self, store):
        self.store = store

    def collection(self, name):
        return Col(self.store, name)

    def transaction(self):
        return Tx(self.store)


@pytest.fixture
def db(monkeypatch):
    store = {
        "child_profiles/p1": {"parentId": "parent", "childAccountId": "child", "pairingStatus": "connected"},
        "child_profiles/p1/chat_messages/m1": {"senderId": "child", "body": "hi", "notificationState": "pending"},
        "child_profiles/p1/access_requests/r1": {"childUid": "child", "appName": "TikTok",
                                                 "requestedMinutes": 30, "notificationState": "pending"},
        "users/parent": {"fcmToken": "tok-parent"},
        "users/child": {"fcmToken": "tok-child"},
    }
    fake = FakeDb(store)
    monkeypatch.setattr(cas, "get_firestore_client", lambda: fake)
    monkeypatch.setattr(cas, "transactional", lambda fn: fn)
    monkeypatch.setattr(cas.firestore, "SERVER_TIMESTAMP", "TS")
    return store


def test_routes_are_registered():
    paths = set(app.openapi()["paths"])
    assert "/chat/events/{profile_id}/{kind}/{event_id}/dispatch" in paths
    assert "/chat/requests/{profile_id}/{request_id}" in paths
    assert "/monitoring/events" in paths
    assert "/internal/monitoring/sweep" in paths


def test_bad_token_returns_403_not_nameerror():
    client = TestClient(app, raise_server_exceptions=True)
    with mock.patch.object(cas, "get_auth_module") as auth:
        auth.return_value.verify_id_token.side_effect = ValueError("bad")
        r = client.post("/chat/events/p1/message/m1/dispatch", headers={"Authorization": "Bearer x"})
    assert r.status_code == 403


def test_message_dispatch_notifies_parent_once(db):
    with mock.patch.object(cas.messaging, "send", return_value="id") as send:
        first = cas.dispatch_event(caller_uid="child", profile_id="p1", kind="message", event_id="m1")
        second = cas.dispatch_event(caller_uid="child", profile_id="p1", kind="message", event_id="m1")
    assert first == {"status": "sent"} and second == {"status": "already_handled"}
    assert send.call_count == 1 and send.call_args.args[0].token == "tok-parent"
    assert db["child_profiles/p1/chat_messages/m1"]["notificationState"] == "sent"


def test_request_dispatch_notifies_parent(db):
    with mock.patch.object(cas.messaging, "send", return_value="id") as send:
        out = cas.dispatch_event(caller_uid="child", profile_id="p1", kind="request", event_id="r1")
    assert out == {"status": "sent"} and send.call_args.args[0].token == "tok-parent"


def test_missing_token_stays_pending_for_sweep(db):
    db["users/parent"] = {}
    out = cas.dispatch_event(caller_uid="child", profile_id="p1", kind="message", event_id="m1")
    assert out == {"status": "no_token"}
    assert db["child_profiles/p1/chat_messages/m1"]["notificationState"] == "pending"


def test_stranger_and_wrong_sender_rejected(db):
    with pytest.raises(cas.ChatAccessError):
        cas.dispatch_event(caller_uid="stranger", profile_id="p1", kind="message", event_id="m1")
    with pytest.raises(cas.ChatAccessError):  # parent cannot dispatch the child's message
        cas.dispatch_event(caller_uid="parent", profile_id="p1", kind="message", event_id="m1")
    assert db["child_profiles/p1/chat_messages/m1"]["notificationState"] == "pending"


@pytest.mark.parametrize("etype", ["usage_warning_threshold", "usage_high_threshold",
                                   "unhealthy_usage_pattern", "late_night_usage"])
def test_usage_event_types_accepted(monkeypatch, etype):
    store = {"child_profiles/p1": {"parentId": "parent", "childAccountId": "child", "pairingStatus": "connected"}}
    monkeypatch.setattr(mas, "get_firestore_client", lambda: FakeDb(store))
    created = []
    monkeypatch.setattr(mas, "_create_and_dispatch", lambda **kw: created.append(kw) or True)
    ev = {"type": etype, "eventId": "usage3h_20261113", "timestampMs": int(time.time() * 1000),
          "subject": "Device usage", "label": "3 hours today"}
    out = mas.accept_child_events(child_uid="child", profile_id="p1", events=[ev])
    assert out["acceptedEventIds"] == ["usage3h_20261113"] and created[0]["kind"] == etype


# ---- immediate approve/decline push, per-app thresholds, parent channel ----

def _decision_store():
    return {
        "child_profiles/p1": {
            "parentId": "parent",
            "childAccountId": "child",
            "parentDisplayName": "Alex Morgan",
            "pairingStatus": "connected",
        },
        "child_profiles/p1/access_requests/r1": {
            "childUid": "child", "appName": "TikTok", "status": "declined",
            "decisionNotificationState": "pending"},
        "users/child": {"limitNotificationToken": "tok-child-limit"},
        "users/parent": {"fcmToken": "tok-parent"},
    }


def test_decision_push_goes_to_child_once(monkeypatch):
    store = _decision_store()
    fake = FakeDb(store)
    monkeypatch.setattr(cas, "transactional", lambda fn: fn)
    monkeypatch.setattr(cas.firestore, "SERVER_TIMESTAMP", "TS")
    with mock.patch.object(cas.messaging, "send", return_value="id") as send:
        cas._notify_decision(fake, "p1", "child", "r1")
        cas._notify_decision(fake, "p1", "child", "r1")  # second call is a no-op
    assert send.call_count == 1
    msg = send.call_args.args[0]
    assert msg.token == "tok-child-limit"
    assert msg.notification.title == "Alex Morgan · App Access Request Denied"
    assert msg.notification.body == "Your request to use TikTok has been denied."
    assert msg.android.notification.channel_id == "wellscreen_chat"
    assert store["child_profiles/p1/access_requests/r1"]["decisionNotificationState"] == "sent"


def test_approved_decision_notification_includes_duration_and_expiry():
    expires_at = cas.dt.datetime(2026, 11, 28, 8, 30, tzinfo=cas.UTC)

    title, body = cas._decision_notification_content(
        {
            "status": "active",
            "appName": "TikTok",
            "approvedMinutes": 30,
            "expiresAt": expires_at,
        },
        "Alex Morgan",
    )

    assert title == "Alex Morgan · App Access Request Approved"
    assert body == (
        "Your request to use TikTok has been approved. "
        "30 minutes granted. Access expires at 4:30 PM."
    )


def test_decision_push_failure_never_breaks_approval(monkeypatch):
    store = _decision_store()
    fake = FakeDb(store)
    monkeypatch.setattr(cas, "transactional", lambda fn: fn)
    monkeypatch.setattr(cas.firestore, "SERVER_TIMESTAMP", "TS")
    with mock.patch.object(cas.messaging, "send", side_effect=RuntimeError("fcm down")):
        cas._notify_decision(fake, "p1", "child", "r1")
    assert store["child_profiles/p1/access_requests/r1"]["decisionNotificationState"] == "failed"


def test_parent_push_uses_alert_channel(db):
    with mock.patch.object(cas.messaging, "send", return_value="id") as send:
        cas.dispatch_event(caller_uid="child", profile_id="p1", kind="message", event_id="m1")
    assert send.call_args.args[0].android.notification.channel_id == "wellscreen_alerts"


@pytest.mark.parametrize("etype,eid", [("app_usage_warning_threshold", "appW_com_tiktok_android_20261113"),
                                       ("app_usage_high_threshold", "appH_com_tiktok_android_20261113")])
def test_per_app_usage_events_accepted(monkeypatch, etype, eid):
    store = {"child_profiles/p1": {"parentId": "parent", "childAccountId": "child", "pairingStatus": "connected"}}
    monkeypatch.setattr(mas, "get_firestore_client", lambda: FakeDb(store))
    created = []
    monkeypatch.setattr(mas, "_create_and_dispatch", lambda **kw: created.append(kw) or True)
    ev = {"type": etype, "eventId": eid, "timestampMs": int(time.time() * 1000),
          "subject": "com.tiktok.android", "label": "TikTok (1h 31m today)"}
    out = mas.accept_child_events(child_uid="child", profile_id="p1", events=[ev])
    assert out["acceptedEventIds"] == [eid] and created[0]["kind"] == etype
    assert "TikTok" in created[0]["body"]


# ---- app access request creation and limits ----

@pytest.fixture
def request_clock(db, monkeypatch):
    db["app_rules/parent"] = {
        "rules": [
            {"packageName": "com.example.one", "appName": "One", "restrictEnabled": True},
            {"packageName": "com.example.two", "appName": "Two", "restrictEnabled": True},
        ],
    }
    clock = [cas.dt.datetime(2026, 11, 16, 12, tzinfo=cas.PHT)]
    monkeypatch.setattr(cas, "_request_now", lambda: clock[0].astimezone(cas.UTC))
    return clock


def _submit(request_id, package="com.example.one", child_uid="child"):
    return cas.submit_access_request(
        child_uid=child_uid, profile_id="p1", request_id=request_id,
        package_name=package, requested_minutes=30,
    )


def test_access_request_cooldown_across_apps(db, request_clock):
    assert _submit("new1")["status"] == "pending"
    assert db["child_profiles/p1/access_requests/new1"]["appName"] == "One"
    with pytest.raises(cas.AppRequestLimitError, match="Please wait"):
        _submit("new2", "com.example.two")
    assert "child_profiles/p1/access_requests/new2" not in db
    request_clock[0] += cas.dt.timedelta(minutes=5)
    assert _submit("new2", "com.example.two")["status"] == "pending"


def test_access_request_daily_cap_and_midnight(db, request_clock):
    request_clock[0] = cas.dt.datetime(2026, 11, 16, 23, 0, tzinfo=cas.PHT)
    for index in range(10):
        request_id = f"quota{index}"
        assert _submit(request_id)["status"] == "pending"
        db[f"child_profiles/p1/access_requests/{request_id}"]["status"] = "declined"
        request_clock[0] += cas.dt.timedelta(minutes=5)
    with pytest.raises(cas.AppRequestLimitError, match="Daily app access limit"):
        _submit("quota10")
    assert "child_profiles/p1/access_requests/quota10" not in db
    request_clock[0] = cas.dt.datetime(2026, 11, 17, 0, 1, tzinfo=cas.PHT)
    assert _submit("quota10")["status"] == "pending"


def test_access_request_duplicate_pending_rejected(db, request_clock):
    _submit("pending1")
    request_clock[0] += cas.dt.timedelta(minutes=6)
    with pytest.raises(cas.ChatAccessError, match="unresolved request"):
        _submit("pending2")
    assert "child_profiles/p1/access_requests/pending2" not in db


def test_access_request_replay_does_not_consume_slot(db, request_clock):
    result = _submit("replay")
    assert _submit("replay") == result
    request_clock[0] += cas.dt.timedelta(minutes=5)
    assert _submit("different", "com.example.two")["status"] == "pending"


def test_access_request_authorization_and_restriction(db, request_clock):
    with pytest.raises(cas.ChatAccessError, match="paired child"):
        _submit("stranger", child_uid="stranger")
    with pytest.raises(cas.ChatAccessError, match="no longer restricted"):
        _submit("unrestricted", "com.example.other")
    assert "child_profiles/p1/access_requests/stranger" not in db
    assert "child_profiles/p1/access_requests/unrestricted" not in db


def test_access_request_route_returns_429(db, request_clock):
    _submit("route_first")
    client = TestClient(app, raise_server_exceptions=True)
    with mock.patch.object(cas, "get_auth_module") as auth:
        auth.return_value.verify_id_token.return_value = {"uid": "child"}
        response = client.post(
            "/chat/requests/p1/route_second",
            headers={"Authorization": "Bearer test-token"},
            json={"packageName": "com.example.two", "requestedMinutes": 30},
        )
    assert response.status_code == 429
    assert "Please wait" in response.json()["detail"]
    assert "child_profiles/p1/access_requests/route_second" not in db
