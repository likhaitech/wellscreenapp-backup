"""Shared setup for the Chapter 4 integration test cases (INT-001 to INT-018).

Each integration case runs the REAL code of two modules together on one
in-memory database (no Firebase project), so the output of Module 1 is the
input of Module 2 - the same hand-off that happens between the phones and
the server in the live system.

Built on the unit-case stand-in (tests/cases/fake_firestore.py), plus the
few extra database features the integration flows use: create() on a
document, range filters (>=) and get_all().
"""
from __future__ import annotations

import datetime as dt
from types import SimpleNamespace

import pytest
from google.api_core.exceptions import AlreadyExists

from app.services import chat_access_service as chat
from app.services import device_admin_alert_service as device_admin
from app.services import monitoring_alerts_service as alerts
from app.services import pairing_service as pairing

from ..cases.fake_firestore import Collection, DocRef, FakeDb, Snapshot

NOW = dt.datetime(2026, 11, 22, 9, 0, tzinfo=dt.timezone.utc)  # 5:00 PM Manila
NOW_MS = int(NOW.timestamp() * 1000)
GUARDIAN = "guardian-uid-0001"
CHILD = "child-uid-0001"
TIKTOK = "com.zhiliaoapp.musically"

_OPS = {
    "==": lambda have, want: have == want,
    "in": lambda have, want: have in want,
    ">=": lambda have, want: have is not None and have >= want,
    ">": lambda have, want: have is not None and have > want,
    "<=": lambda have, want: have is not None and have <= want,
    "<": lambda have, want: have is not None and have < want,
}


class IntDocRef(DocRef):
    def create(self, data: dict) -> None:
        if self.path in self._db.docs:
            raise AlreadyExists(self.path)
        self._db._write(self, data)

    def collection(self, name: str) -> "IntCollection":
        return IntCollection(self._db, f"{self.path}/{name}")


class IntCollection(Collection):
    def document(self, doc_id: str | None = None) -> IntDocRef:
        base = super().document(doc_id)
        return IntDocRef(self._db, self._name, base.id)

    def where(self, field=None, op=None, value=None, *, filter=None) -> "IntCollection":
        if filter is not None:
            field, op, value = filter.field_path, filter.op_string, filter.value
        return IntCollection(self._db, self._name, self._filters + [(field, op, value)],
                             self._order, self._count)

    def order_by(self, field, direction="ASCENDING") -> "IntCollection":
        return IntCollection(self._db, self._name, self._filters, (field, direction), self._count)

    def limit(self, count: int) -> "IntCollection":
        return IntCollection(self._db, self._name, self._filters, self._order, count)

    def stream(self, transaction=None):
        prefix = self._name + "/"
        rows = []
        for path, data in self._db.docs.items():
            if not path.startswith(prefix) or "/" in path[len(prefix):]:
                continue
            if all(_OPS[op](data.get(field), value) for field, op, value in self._filters):
                rows.append(Snapshot(IntDocRef(self._db, self._name, path[len(prefix):]), data))
        if self._order:
            field, direction = self._order
            rows.sort(key=lambda r: r.to_dict().get(field),
                      reverse=str(direction).upper().startswith("DESC"))
        return iter(rows[: self._count] if self._count else rows)


class IntDb(FakeDb):
    def collection(self, name: str) -> IntCollection:
        return IntCollection(self, name)

    def get_all(self, refs):
        return [ref.get() for ref in refs]


@pytest.fixture
def system(monkeypatch):
    """The real pairing, monitoring alerts, Device Admin alert and chat
    services on one shared database, with push and SMS recorded instead of
    sent. A guardian and a child account already exist (registered)."""
    db = IntDb({
        f"users/{GUARDIAN}": {"role": "parent", "fullName": "Maria Santos",
                              "email": "maria@example.com"},
        f"users/{CHILD}": {"role": "child", "fullName": "Ana Santos",
                           "email": "ana@example.com"},
    })
    clock = {"now": NOW}
    pushes: list[dict] = []
    texts: list[dict] = []

    def push(**kwargs):
        pushes.append(kwargs)
        return {"status": "sent", "message_id": f"push-{len(pushes)}"}

    def sms(**kwargs):
        texts.append(kwargs)
        return {"status": "accepted"}

    for module in (pairing, alerts, device_admin, chat):
        monkeypatch.setattr(module, "get_firestore_client", lambda: db)
    for module in (pairing, chat):
        monkeypatch.setattr(module, "transactional", lambda fn: fn)
    monkeypatch.setattr(pairing, "_now", lambda: clock["now"])
    monkeypatch.setattr(chat, "_request_now", lambda: clock["now"])
    monkeypatch.setattr(alerts, "_utcnow", lambda: clock["now"])
    monkeypatch.setattr(device_admin, "_utcnow", lambda: clock["now"])
    monkeypatch.setattr(alerts, "send_alert_notification", push)
    monkeypatch.setattr(alerts, "_send_sms", sms)
    return SimpleNamespace(db=db, clock=clock, pushes=pushes, texts=texts)


def pair_child(system, child_name: str = "Ana") -> str:
    """Guardian generates a code and the child redeems it (real pairing
    service). Returns the child profile ID."""
    made = pairing.generate_pairing_code(parent_uid=GUARDIAN, child_name=child_name)
    result = pairing.redeem_pairing_code(child_uid=CHILD, code=made["code"])
    assert result["status"] == "connected"
    return made["childProfileId"]


def guardian_alerts(system, profile_id: str) -> list[dict]:
    """What the guardian's Notifications screen reads:
    child_profiles/{id}/monitoring_alerts."""
    prefix = f"child_profiles/{profile_id}/monitoring_alerts/"
    return [data for path, data in system.db.docs.items() if path.startswith(prefix)]
