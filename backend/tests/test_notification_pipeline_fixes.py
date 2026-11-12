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


class Tx:
    def __init__(self, store):
        self.store = store

    def update(self, ref, data):
        ref.update(data)


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
