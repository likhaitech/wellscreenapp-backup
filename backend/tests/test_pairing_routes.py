from fastapi.testclient import TestClient

from app.main import app
from app.routes import pairing as pairing_routes
from app.services.chat_access_service import ChatAccessError
from app.services.pairing_service import (
    PairingConflictError,
    PairingError,
    PairingForbiddenError,
    PairingRateLimitError,
)


client = TestClient(app)

AUTH_HEADERS = {
    "Authorization": "Bearer test-firebase-token",
}


def test_generate_pairing_code_success(monkeypatch):
    def fake_auth(_authorization):
        return "parent-123"

    def fake_generate(*, parent_uid, child_name):
        assert parent_uid == "parent-123"
        assert child_name == "John"

        return {
            "code": "583921",
            "childProfileId": "profile-123",
            "expiresAt": "2026-11-17T10:15:00+00:00",
        }

    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        fake_auth,
    )
    monkeypatch.setattr(
        pairing_routes,
        "generate_pairing_code",
        fake_generate,
    )

    response = client.post(
        "/pairing/code",
        json={"childName": "John"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 200
    assert response.json()["code"] == "583921"
    assert response.json()["childProfileId"] == "profile-123"


def test_redeem_pairing_code_success(monkeypatch):
    def fake_auth(_authorization):
        return "child-123"

    def fake_redeem(*, child_uid, code):
        assert child_uid == "child-123"
        assert code == "583921"

        return {
            "parentId": "parent-123",
            "childProfileId": "profile-123",
            "status": "connected",
        }

    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        fake_auth,
    )
    monkeypatch.setattr(
        pairing_routes,
        "redeem_pairing_code",
        fake_redeem,
    )

    response = client.post(
        "/pairing/redeem",
        json={"code": "583921"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 200
    assert response.json()["status"] == "connected"
    assert response.json()["parentId"] == "parent-123"


def test_generate_rejects_empty_child_name():
    response = client.post(
        "/pairing/code",
        json={"childName": ""},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 422


def test_redeem_rejects_invalid_code_format():
    response = client.post(
        "/pairing/redeem",
        json={"code": "123"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 422


def test_invalid_firebase_token_returns_401(monkeypatch):
    def fake_auth(_authorization):
        raise ChatAccessError("Invalid Firebase token")

    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        fake_auth,
    )

    response = client.post(
        "/pairing/code",
        json={"childName": "John"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 401


def test_non_parent_cannot_generate_code(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "child-123",
    )

    def fake_generate(**_kwargs):
        raise PairingForbiddenError(
            "Only parent accounts can generate pairing codes."
        )

    monkeypatch.setattr(
        pairing_routes,
        "generate_pairing_code",
        fake_generate,
    )

    response = client.post(
        "/pairing/code",
        json={"childName": "John"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 403


def test_redeem_rate_limit_returns_429(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "child-123",
    )

    def fake_redeem(**_kwargs):
        raise PairingRateLimitError("Too many attempts.")

    monkeypatch.setattr(
        pairing_routes,
        "redeem_pairing_code",
        fake_redeem,
    )

    response = client.post(
        "/pairing/redeem",
        json={"code": "583921"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 429


def test_redeem_already_used_code_returns_409(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "child-123",
    )

    def fake_redeem(**_kwargs):
        raise PairingConflictError(
            "This pairing code has already been used."
        )

    monkeypatch.setattr(
        pairing_routes,
        "redeem_pairing_code",
        fake_redeem,
    )

    response = client.post(
        "/pairing/redeem",
        json={"code": "583921"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 409


def test_redeem_expired_code_returns_400(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "child-123",
    )

    def fake_redeem(**_kwargs):
        raise PairingError("This pairing code has expired.")

    monkeypatch.setattr(
        pairing_routes,
        "redeem_pairing_code",
        fake_redeem,
    )

    response = client.post(
        "/pairing/redeem",
        json={"code": "583921"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 400



def test_unpair_child_device_success(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "parent-123",
    )

    def fake_unpair(*, parent_uid, child_profile_id):
        assert parent_uid == "parent-123"
        assert child_profile_id == "profile-123"

        return {
            "childProfileId": child_profile_id,
            "status": "unpaired",
        }

    monkeypatch.setattr(
        pairing_routes,
        "unpair_child_device",
        fake_unpair,
    )

    response = client.post(
        "/pairing/unpair",
        json={"childProfileId": "profile-123"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 200
    assert response.json()["status"] == "unpaired"


def test_unpair_requires_authentication(monkeypatch):
    def fake_auth(_authorization):
        raise ChatAccessError("Invalid Firebase token")

    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        fake_auth,
    )

    response = client.post(
        "/pairing/unpair",
        json={"childProfileId": "profile-123"},
    )

    assert response.status_code == 401


def test_unpair_forbidden_returns_403(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "other-parent",
    )

    def fake_unpair(**_kwargs):
        raise PairingForbiddenError(
            "You are not authorized to remove this device."
        )

    monkeypatch.setattr(
        pairing_routes,
        "unpair_child_device",
        fake_unpair,
    )

    response = client.post(
        "/pairing/unpair",
        json={"childProfileId": "profile-123"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 403


def test_unpair_conflict_returns_409(monkeypatch):
    monkeypatch.setattr(
        pairing_routes,
        "authenticated_uid",
        lambda _authorization: "parent-123",
    )

    def fake_unpair(**_kwargs):
        raise PairingConflictError(
            "This device is not currently connected."
        )

    monkeypatch.setattr(
        pairing_routes,
        "unpair_child_device",
        fake_unpair,
    )

    response = client.post(
        "/pairing/unpair",
        json={"childProfileId": "profile-123"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 409


def test_unpair_rejects_invalid_profile_id():
    response = client.post(
        "/pairing/unpair",
        json={"childProfileId": "invalid/profile"},
        headers=AUTH_HEADERS,
    )

    assert response.status_code == 422