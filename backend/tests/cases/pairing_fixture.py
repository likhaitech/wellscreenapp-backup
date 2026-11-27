"""Shared setup for the pairing test cases: the real pairing service with a
fake database, a guardian account and two child accounts."""
from __future__ import annotations

import datetime as dt

import pytest

from app.services import pairing_service as pairing

from .fake_firestore import install

NOW = dt.datetime(2026, 11, 22, 9, 0, tzinfo=dt.timezone.utc)
PARENT = "parent-uid-0001"
CHILD = "child-uid-0001"
CHILD2 = "child-uid-0002"


@pytest.fixture
def env(monkeypatch):
    db = install(monkeypatch, pairing, {
        f"users/{PARENT}": {"role": "parent", "fullName": "Maria Santos",
                            "email": "maria@example.com"},
        f"users/{CHILD}": {"role": "child", "fullName": "Ana Santos",
                           "email": "ana@example.com"},
        f"users/{CHILD2}": {"role": "child", "fullName": "Ben Cruz",
                            "email": "ben@example.com"},
    })
    clock = {"now": NOW}
    monkeypatch.setattr(pairing, "_now", lambda: clock["now"])
    return db, clock


def error_of(call) -> str:
    try:
        call()
    except pairing.PairingError as error:
        return str(error)
    raise AssertionError("expected the pairing service to refuse")
