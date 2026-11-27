"""CASE-036 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_036.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_036(env):
    db, clock = env

    def body() -> str:
        message = error_of(lambda: pairing.redeem_pairing_code(child_uid=CHILD, code="999999"))
        assert message == "Pairing code not found."
        return f"Code 999999 (never created): refused with \"{message}\""

    run_case(
        "CASE-036",
        file="backend/tests/cases/test_pairing_service_case_036.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Child enters a six-digit code that does not exist.',
        expected='Pairing fails with “Pairing code not found.”',
        body=body,
    )
