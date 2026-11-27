"""CASE-034 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_034.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_034(env):
    db, clock = env

    def body() -> str:
        code = pairing.generate_pairing_code(parent_uid=PARENT, child_name="Ana")["code"]
        clock["now"] = NOW + dt.timedelta(minutes=16)
        message = error_of(lambda: pairing.redeem_pairing_code(child_uid=CHILD, code=code))
        assert message == "This pairing code has expired."
        return f"Code {code} redeemed 16 minutes later: refused with \"{message}\""

    run_case(
        "CASE-034",
        file="backend/tests/cases/test_pairing_service_case_034.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Child enters a pairing code more than 15 minutes old.',
        expected='Pairing fails with “This pairing code has expired.”',
        body=body,
    )
