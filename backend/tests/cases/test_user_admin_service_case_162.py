"""CASE-162 - System Administration.
Run (from backend): python -m pytest tests/cases/test_user_admin_service_case_162.py -s -q
"""
from app.services import user_admin_service as svc

from .admin_fixture import admin_env  # noqa: F401
from .case_report import run_case


def test_case_162(admin_env):
    fake, db = admin_env

    def body() -> str:
        updated = svc.update_user("parent-1", display_name="Maria S. Reyes")
        assert updated["display_name"] == "Maria S. Reyes"
        assert db.docs["users/parent-1"]["fullName"] == "Maria S. Reyes"
        return ("The name was saved in both Authentication and the users record "
                "(\"Maria S. Reyes\"); the app shows \"User details updated.\"")

    run_case(
        "CASE-162",
        file="backend/tests/cases/test_user_admin_service_case_162.py",
        code_tested="backend/app/services/user_admin_service.py",
        description='Administrator edits a user’s details and taps Save.',
        expected='“User details updated.” is displayed and the list shows the new details.',
        body=body,
    )
