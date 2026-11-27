"""CASE-167 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_167.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_167(admin_env):
    fake, db = admin_env

    def body() -> str:
        svc.delete_user("temp-1")
        emails = [u["email"] for u in svc.list_users()]
        assert "test@example.com" not in emails
        assert "users/temp-1" not in db.docs
        return f"test@example.com was deleted; the list now has {len(emails)} accounts without it"

    run_case(
        "CASE-167",
        file="backend/tests/cases/test_user_admin_service_case_167.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator deletes an account and confirms “Delete account?”.',
        expected='“Account deleted.” is displayed and the account is removed from the list.',
        body=body,
    )
