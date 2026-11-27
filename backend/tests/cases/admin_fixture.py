"""Shared setup for the System Administration cases: the real user admin
service with Firebase Authentication and Firestore replaced by in-memory
stand-ins (no Firebase project)."""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.services import user_admin_service as svc

from .fake_firestore import FakeDb


class FakeAuth:
    """Firebase Authentication accounts kept in a dict."""

    def __init__(self):
        self.users: dict[str, SimpleNamespace] = {}
        self.revoked: list[str] = []

    def add(self, uid, email, name, role, password="Start#123"):
        self.users[uid] = SimpleNamespace(
            uid=uid, email=email, display_name=name, disabled=False,
            email_verified=True, custom_claims={"role": role, "admin": role == "admin"},
            user_metadata=SimpleNamespace(creation_timestamp=1, last_sign_in_timestamp=2),
            password=password)

    def list_users(self):
        users = list(self.users.values())
        return SimpleNamespace(iterate_all=lambda: iter(users))

    def get_user(self, uid):
        return self.users[uid]

    def update_user(self, uid, **changes):
        for key, value in changes.items():
            setattr(self.users[uid], key, value)

    def set_custom_user_claims(self, uid, claims):
        self.users[uid].custom_claims = claims

    def revoke_refresh_tokens(self, uid):
        self.revoked.append(uid)

    def delete_user(self, uid):
        self.users.pop(uid)

    def can_sign_in(self, email, password) -> bool:
        user = next((u for u in self.users.values() if u.email == email), None)
        return bool(user and not user.disabled and user.password == password)


@pytest.fixture
def admin_env(monkeypatch):
    fake = FakeAuth()
    fake.add("parent-1", "maria@example.com", "Maria Santos", "parent")
    fake.add("child-1", "ana@example.com", "Ana Santos", "child")
    fake.add("admin-1", "admin@wellscreen.app", "Admin", "admin")
    db = FakeDb({
        "users/parent-1": {"role": "parent", "fullName": "Maria Santos"},
        "users/child-1": {"role": "child", "fullName": "Ana Santos"},
        "users/temp-1": {"role": "parent", "fullName": "Test Account"},
    })
    fake.add("temp-1", "test@example.com", "Test Account", "parent")
    monkeypatch.setattr(svc, "initialize_firebase", lambda: None)
    monkeypatch.setattr(svc, "get_firestore_client", lambda: db)
    for name in ("list_users", "get_user", "update_user", "set_custom_user_claims",
                 "revoke_refresh_tokens", "delete_user"):
        monkeypatch.setattr(svc.auth, name, getattr(fake, name))
    return fake, db
