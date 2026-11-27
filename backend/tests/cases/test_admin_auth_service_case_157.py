"""CASE-157 - System Administration.
Run (from backend): python -m pytest tests/cases/test_admin_auth_service_case_157.py -s -q
"""
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.services import admin_auth_service as guard

from .case_report import run_case


def test_case_157(monkeypatch):
    # The guardian's sign-in token says role "parent".
    monkeypatch.setattr(guard, "initialize_firebase", lambda: None)
    monkeypatch.setattr(guard.auth, "verify_id_token",
                        lambda token, check_revoked=True: {"uid": "parent-1", "role": "parent"})

    def body() -> str:
        try:
            guard.require_admin(HTTPAuthorizationCredentials(scheme="Bearer", credentials="guardian-token"))
        except HTTPException as error:
            assert error.status_code == 403
            return (f"The server refused the guardian's admin request: {error.status_code} "
                    f"\"{error.detail}\" (the app opens the Guardian Dashboard instead)")
        raise AssertionError("guardian was let in")

    run_case(
        "CASE-157",
        file="backend/tests/cases/test_admin_auth_service_case_157.py",
        code_tested="backend/app/services/admin_auth_service.py",
        description='Guardian account tries to open the administrator pages.',
        expected='The guardian is sent to the Guardian Dashboard; the server rejects administrator requests from non-administrators.',
        body=body,
    )
