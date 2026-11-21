"""CASE-164 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_164.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_164(admin_env):
    fake, db = admin_env

    def body() -> str:
        svc.update_user("parent-1", password="NewPass#2026")
        assert fake.can_sign_in("maria@example.com", "NewPass#2026")
        assert not fake.can_sign_in("maria@example.com", "Start#123")
        return ("The new password was set; maria@example.com can log in with it "
                "and the old one no longer works (\"Password updated.\" in the app)")

    run_case(
        "CASE-164",
        file="backend/tests/cases/test_user_admin_service_case_164.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator sets a valid new password for a user.',
        expected='“Password updated.” is displayed and the user can log in with the new password.',
        body=body,
    )
