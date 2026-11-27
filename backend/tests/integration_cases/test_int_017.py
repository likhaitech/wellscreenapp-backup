
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import auth

from app.services import user_admin_service as admin
from app.services import user_auth_service

from ..cases.admin_fixture import admin_env  # noqa: F401
from ..cases.case_report import run_case

APP_LOGIN_MESSAGES = Path(__file__).resolve().parents[3] / "mobile_app/lib/services/login_error_message.dart"


def test_int_017(admin_env, monkeypatch):
    fake, db = admin_env
    tokens = {"token-of-maria": "parent-1"}

    def verify_id_token(token, check_revoked=False):
        uid = tokens[token]
        if check_revoked and (uid in fake.revoked or fake.users[uid].disabled):
            raise auth.RevokedIdTokenError("revoked")
        return {"uid": uid}

    monkeypatch.setattr(user_auth_service, "initialize_firebase", lambda: None)
    monkeypatch.setattr(user_auth_service.auth, "verify_id_token", verify_id_token)
    signed_in = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token-of-maria")

    def body() -> str:
        assert fake.can_sign_in("maria@example.com", "Start#123")
        assert user_auth_service.require_user(signed_in)["uid"] == "parent-1"

        updated = admin.update_user("parent-1", disabled=True)
        assert updated["disabled"] is True

        assert not fake.can_sign_in("maria@example.com", "Start#123")
        with pytest.raises(HTTPException) as refused:
            user_auth_service.require_user(signed_in)
        assert refused.value.status_code == 401

        # The app shows Firebase's "user-disabled" as this message.
        app_text = APP_LOGIN_MESSAGES.read_text(encoding="utf-8")
        assert "This account has been disabled." in app_text
        return ("After the administrator deactivated Maria, her login is refused, her open "
                "session is signed out (401), and the app shows \"This account has been "
                "disabled.\"")

    run_case(
        "INT-017",
        file="backend/tests/integration_cases/test_int_017.py",
        code_tested="backend/app/services/user_admin_service.py + user_auth_service.py",
        description="Administrator deactivates a user account (System Administration -> Authentication).",
        expected="The deactivated user cannot log in and sees “This account has been disabled.”",
        body=body,
    )
