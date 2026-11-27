"""Shared setup for the chat app-time cases: the real chat access service on
an in-memory database with a paired child whose TikTok is blocked."""
from __future__ import annotations

import datetime as dt

import pytest

from app.services import chat_access_service as chat

from .fake_firestore import install

NOW = dt.datetime(2026, 11, 22, 9, 0, tzinfo=dt.timezone.utc)
TIKTOK = "com.zhiliaoapp.musically"


@pytest.fixture
def chat_env(monkeypatch):
    db = install(monkeypatch, chat, {
        "users/parent-1": {"role": "parent"},
        "users/child-1": {"role": "child"},
        "child_profiles/profile-1": {"parentId": "parent-1", "childAccountId": "child-1",
                                     "pairingStatus": "connected"},
        "app_rules/parent-1": {"rules": [{"packageName": TIKTOK, "appName": "TikTok",
                                          "restrictEnabled": True}]},
    })
    clock = {"now": NOW}
    monkeypatch.setattr(chat, "_request_now", lambda: clock["now"])
    return db, clock


def ask(minutes: int = 15, request_id: str = "req-0001") -> dict:
    return chat.submit_access_request(child_uid="child-1", profile_id="profile-1",
                                      request_id=request_id, package_name=TIKTOK,
                                      requested_minutes=minutes)
