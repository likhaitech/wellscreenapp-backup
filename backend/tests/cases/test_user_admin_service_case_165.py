"""CASE-165 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_165.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_165(admin_env):
    fake, db = admin_env

    def body() -> str:
        updated = svc.update_user("parent-1", disabled=True)
        assert updated["disabled"] is True
        assert "parent-1" in fake.revoked
        assert not fake.can_sign_in("maria@example.com", "Start#123")
        return ("The account is disabled and its sessions were signed out; the next "
                "login is refused (shown as \"This account has been disabled.\")")

    run_case(
        "CASE-165",
        file="backend/tests/cases/test_user_admin_service_case_165.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator deactivates an account and confirms.',
        expected='“Account deactivated.” is displayed; the user’s next login fails with “This account has been disabled.”',
        body=body,
    )
