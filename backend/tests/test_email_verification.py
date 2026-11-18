"""Generating a pairing code requires a verified guardian email (accounts
created before the cutoff are exempt). Redeeming a code does not: children
may have no email. Firebase Auth is faked - no real project is touched."""
from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routes import pairing as pairing_routes
from app.services import email_verification_service as svc

client = TestClient(app)
AUTH_HEADERS = {"Authorization": "Bearer test-firebase-token"}

BEFORE = svc.ENFORCED_FROM_MS - 1
AFTER = svc.ENFORCED_FROM_MS + 60_000


def _fake_auth(*, verified: bool, created_ms):
    user = SimpleNamespace(
        email_verified=verified,
        user_metadata=SimpleNamespace(creation_timestamp=created_ms),
    )
    return SimpleNamespace(get_user=lambda uid: user)


class TestEnsureEmailVerified:
    def test_verified_new_account_passes(self):
        svc.ensure_email_verified(
            "u1", auth_module=_fake_auth(verified=True, created_ms=AFTER)
        )

    def test_unverified_new_account_is_refused(self):
        with pytest.raises(svc.EmailNotVerifiedError):
            svc.ensure_email_verified(
                "u1", auth_module=_fake_auth(verified=False, created_ms=AFTER)
            )

    def test_account_created_exactly_at_cutoff_is_refused(self):
        with pytest.raises(svc.EmailNotVerifiedError):
            svc.ensure_email_verified(
                "u1",
                auth_module=_fake_auth(
                    verified=False, created_ms=svc.ENFORCED_FROM_MS
                ),
            )

    def test_unverified_account_from_before_cutoff_passes(self):
        svc.ensure_email_verified(
            "u1", auth_module=_fake_auth(verified=False, created_ms=BEFORE)
        )

    def test_unknown_creation_time_is_refused(self):
        with pytest.raises(svc.EmailNotVerifiedError):
            svc.ensure_email_verified(
                "u1", auth_module=_fake_auth(verified=False, created_ms=None)
            )


def _patch_routes(monkeypatch, *, check):
    monkeypatch.setattr(pairing_routes, "authenticated_uid", lambda _a: "uid-1")
    monkeypatch.setattr(pairing_routes, "ensure_email_verified", check)
    called = {"generate": 0, "redeem": 0}

    def fake_generate(**_kwargs):
        called["generate"] += 1
        return {
            "code": "583921",
            "childProfileId": "p1",
            "expiresAt": "2026-11-18T10:15:00+00:00",
        }

    def fake_redeem(**_kwargs):
        called["redeem"] += 1
        return {"parentId": "parent-1", "childProfileId": "p1"}

    monkeypatch.setattr(pairing_routes, "generate_pairing_code", fake_generate)
    monkeypatch.setattr(pairing_routes, "redeem_pairing_code", fake_redeem)
    return called


def _refuse(_uid):
    raise svc.EmailNotVerifiedError(svc.EMAIL_NOT_VERIFIED_MESSAGE)


def test_unverified_guardian_cannot_generate_a_code(monkeypatch):
    called = _patch_routes(monkeypatch, check=_refuse)

    response = client.post(
        "/pairing/code", json={"childName": "John"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 403
    assert response.headers["X-WellScreen-Error"] == "email_not_verified"
    assert "Verify your email" in response.json()["detail"]
    assert called["generate"] == 0, "no code for an unverified guardian"


def test_verified_guardian_can_generate_a_code(monkeypatch):
    called = _patch_routes(monkeypatch, check=lambda _uid: None)

    response = client.post(
        "/pairing/code", json={"childName": "John"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    assert called["generate"] == 1


def test_child_without_verified_email_can_still_redeem(monkeypatch):
    # The code itself comes from a verified guardian.
    called = _patch_routes(monkeypatch, check=_refuse)

    response = client.post(
        "/pairing/redeem", json={"code": "583921"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 200
    assert called["redeem"] == 1


def test_check_failure_fails_closed(monkeypatch):
    def broken(_uid):
        raise RuntimeError("firebase unavailable")

    called = _patch_routes(monkeypatch, check=broken)

    response = client.post(
        "/pairing/code", json={"childName": "John"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 503
    assert called["generate"] == 0


def test_unpair_does_not_require_verified_email(monkeypatch):
    # Removing a child must always stay possible.
    monkeypatch.setattr(pairing_routes, "authenticated_uid", lambda _a: "uid-1")
    monkeypatch.setattr(pairing_routes, "ensure_email_verified", _refuse)
    monkeypatch.setattr(
        pairing_routes,
        "unpair_child_device",
        lambda **_kwargs: {"status": "unpaired"},
    )

    response = client.post(
        "/pairing/unpair", json={"childProfileId": "p1"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 200
