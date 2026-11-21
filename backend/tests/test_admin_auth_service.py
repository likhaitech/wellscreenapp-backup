"""Tests for require_admin() in app/services/admin_auth_service.py - the
gate every /admin/* route sits behind (admin_logs, admin_overview,
admin_users). Covers the branches that decide who gets in: no credentials
at all, a revoked token, a token that plain fails to verify, a valid token
with no admin claim, and the two independent ways a token IS recognized as
admin (`admin: true` vs `role: "admin"`) - both are real code paths
system_log_service-consuming routes rely on.

firebase_admin.auth.verify_id_token and initialize_firebase are mocked -
no real Firebase project is touched, no network call is made.
"""
from __future__ import annotations

from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import auth

from app.services import admin_auth_service as svc


def _creds(token: str = "some-token") -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


class TestRequireAdmin:
    def test_missing_credentials_returns_401(self):
        with pytest.raises(HTTPException) as exc_info:
            svc.require_admin(credentials=None)

        assert exc_info.value.status_code == 401

    def test_revoked_token_returns_401_with_specific_message(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            side_effect=auth.RevokedIdTokenError("revoked"),
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_admin(credentials=_creds())

        assert exc_info.value.status_code == 401
        # Distinct copy from the generic "invalid token" message below - the
        # caller should be told to sign in again, not that their token was
        # malformed.
        assert "revoked" in exc_info.value.detail.lower()

    def test_unparseable_token_returns_401(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "verify_id_token", side_effect=ValueError("bad token")
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_admin(credentials=_creds())

        assert exc_info.value.status_code == 401

    def test_valid_token_without_admin_claim_is_forbidden(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "verify_id_token", return_value={"uid": "u1"}
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_admin(credentials=_creds())

        assert exc_info.value.status_code == 403

    def test_admin_boolean_claim_is_accepted(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            return_value={"uid": "u1", "admin": True},
        ):
            result = svc.require_admin(credentials=_creds())

        assert result == {"uid": "u1", "admin": True}

    def test_role_admin_claim_is_accepted_even_without_admin_boolean(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            return_value={"uid": "u1", "role": "admin"},
        ):
            result = svc.require_admin(credentials=_creds())

        assert result == {"uid": "u1", "role": "admin"}

    def test_role_field_with_non_admin_value_is_forbidden(self):
        # A "role" claim that exists but isn't literally "admin" (e.g. a
        # regular parent/child account) must not slip through.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            return_value={"uid": "u1", "role": "user"},
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_admin(credentials=_creds())

        assert exc_info.value.status_code == 403

    def test_verify_id_token_is_called_with_check_revoked_true(self):
        # This is the actual behavior the comment in admin_auth_service.py
        # promises: without check_revoked=True, a disabled admin's
        # already-issued token would keep passing for up to an hour.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            return_value={"uid": "u1", "admin": True},
        ) as mock_verify:
            svc.require_admin(credentials=_creds("tok-123"))

        mock_verify.assert_called_once_with("tok-123", check_revoked=True)
