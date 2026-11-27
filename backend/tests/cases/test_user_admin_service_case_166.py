"""CASE-166 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_166.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_166(admin_env):
    fake, db = admin_env
    fake.users["parent-1"].disabled = True

    def body() -> str:
        updated = svc.update_user("parent-1", disabled=False)
        assert updated["disabled"] is False
        assert fake.can_sign_in("maria@example.com", "Start#123")
        return "The account is active again and maria@example.com can log in (\"Account reactivated.\")"

    run_case(
        "CASE-166",
        file="backend/tests/cases/test_user_admin_service_case_166.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator reactivates a deactivated account.',
        expected='“Account reactivated.” is displayed and the user can log in again.',
        body=body,
    )
