"""CASE-040 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_040.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_040(env):
    db, clock = env

    def body() -> str:
        code = pairing.generate_pairing_code(parent_uid=PARENT, child_name="Ana")["code"]
        pairing.redeem_pairing_code(child_uid=CHILD, code=code)
        message = error_of(lambda: pairing.redeem_pairing_code(child_uid=CHILD2, code=code))
        assert message == "This pairing code has already been used."
        return f"Ana paired with {code}; Ben's try with the same code is refused with \"{message}\""

    run_case(
        "CASE-040",
        file="backend/tests/cases/test_pairing_service_case_040.py",
        code_tested="backend/app/services/pairing_service.py",
        description='A second child enters a code that was already used.',
        expected='Pairing fails with “This pairing code has already been used.”',
        body=body,
    )
