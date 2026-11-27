"""CASE-160 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_160.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_160(admin_env):
    fake, db = admin_env
    fake.users["child-1"].disabled = True

    def body() -> str:
        users = svc.list_users()
        shown = {u["email"]: ("Deactivated" if u["disabled"] else "Active") for u in users}
        assert shown["maria@example.com"] == "Active"
        assert shown["ana@example.com"] == "Deactivated"
        return f"{len(users)} accounts listed: " + ", ".join(f"{e} ({s})" for e, s in shown.items())

    run_case(
        "CASE-160",
        file="backend/tests/cases/test_user_admin_service_case_160.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator opens Manage users.',
        expected='All guardian and child accounts are listed with an Active or Deactivated status.',
        body=body,
    )
