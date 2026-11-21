"""CASE-035 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_035.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_035(env):
    db, clock = env

    def body() -> str:
        message = error_of(lambda: pairing.redeem_pairing_code(child_uid=CHILD, code="12345"))
        assert message == "Please enter a valid 6-digit pairing code."
        return f"Code 12345 (five digits): refused with \"{message}\""

    run_case(
        "CASE-035",
        file="backend/tests/cases/test_pairing_service_case_035.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Child enters fewer than six digits.',
        expected='Pairing fails with “Please enter a valid 6-digit pairing code.”',
        body=body,
    )
