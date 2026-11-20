"""New website alert kinds: review a site the checks are unsure about, and the
child's "ask my parent to allow this site" request. Both are push-only."""
from __future__ import annotations

import time
from types import SimpleNamespace

import pytest

from app.services import monitoring_alerts_service as mas


class _Ref:
    def __init__(self, store, path):
        self.store, self.path = store, path

    def get(self):
        d = self.store.get(self.path)
        return SimpleNamespace(exists=d is not None, to_dict=lambda: dict(d or {}))

    def create(self, data):
        if self.path in self.store:
            raise mas.AlreadyExists("exists")
        self.store[self.path] = dict(data)

    def update(self, data):
        self.store[self.path].update(data)

    def collection(self, name):
        return _Col(self.store, f"{self.path}/{name}")


class _Col:
    def __init__(self, store, path):
        self.store, self.path = store, path

    def document(self, doc_id):
        return _Ref(self.store, f"{self.path}/{doc_id}")


class _Db:
    def __init__(self, store):
        self.store = store

    def collection(self, name):
        return _Col(self.store, name)


@pytest.fixture
def store(monkeypatch):
    data = {"child_profiles/p1": {"parentId": "parent", "childAccountId": "child",
                                  "pairingStatus": "connected"}}
    monkeypatch.setattr(mas, "get_firestore_client", lambda: _Db(data))
    return data


def _event(kind, eid, subject="casino-example.com"):
    return {"type": kind, "eventId": eid, "timestampMs": int(time.time() * 1000),
            "subject": subject, "label": f"{subject} (the page shows some gambling words)"}


@pytest.mark.parametrize("kind,eid,title", [
    ("site_review_needed", "rev_casino-example_com_20261120", "Review this website"),
    ("site_access_request", "req_casino-example_com_1763600000", "Your child asked to open a website"),
])
def test_site_alert_kinds_create_one_push_only_alert(store, monkeypatch, kind, eid, title):
    pushes, sms = [], []
    monkeypatch.setattr(mas, "_push", lambda **kw: pushes.append(kw) or {"status": "failed"})
    monkeypatch.setattr(mas, "_send_sms", lambda **kw: sms.append(kw) or {"status": "sent"})

    out = mas.accept_child_events(child_uid="child", profile_id="p1", events=[_event(kind, eid)])
    again = mas.accept_child_events(child_uid="child", profile_id="p1", events=[_event(kind, eid)])

    assert out["acceptedEventIds"] == [eid] and again["acceptedEventIds"] == [eid]
    alert = store[f"child_profiles/p1/monitoring_alerts/child_{eid}"]
    assert alert["kind"] == kind and alert["title"] == title
    assert alert["details"]["subject"] == "casino-example.com"
    assert "casino-example.com" in alert["body"]
    # Even when the push fails, these never fall back to a paid SMS.
    assert alert["smsStatus"] == "not_requested" and sms == []
    assert len(pushes) == 1  # duplicate event ID did not notify twice


def test_other_kinds_still_use_sms_backup(store, monkeypatch):
    monkeypatch.setattr(mas, "_push", lambda **kw: {"status": "failed"})
    monkeypatch.setattr(mas, "_send_sms", lambda **kw: {"status": "sent"})
    ev = _event("restricted_content_attempt", "rra_casino_example_3")
    mas.accept_child_events(child_uid="child", profile_id="p1", events=[ev])
    assert store["child_profiles/p1/monitoring_alerts/child_rra_casino_example_3"]["smsStatus"] == "sent"


def test_unknown_site_kind_rejected(store, monkeypatch):
    monkeypatch.setattr(mas, "_push", lambda **kw: {"status": "sent"})
    out = mas.accept_child_events(child_uid="child", profile_id="p1",
                                  events=[_event("site_auto_allow", "rev_whatever_20261120")])
    assert out["acceptedEventIds"] == []


def test_stranger_cannot_send_site_request(store):
    with pytest.raises(PermissionError):
        mas.accept_child_events(child_uid="stranger", profile_id="p1",
                                events=[_event("site_access_request", "req_x_1234567890")])
