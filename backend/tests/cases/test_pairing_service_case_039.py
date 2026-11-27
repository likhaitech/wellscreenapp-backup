
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_039(env):
    db, clock = env

    def body() -> str:
        for guess in range(10):
            message = error_of(lambda: pairing.redeem_pairing_code(
                child_uid=CHILD, code=f"90000{guess}"))
            assert message == "Pairing code not found."
        message = error_of(lambda: pairing.redeem_pairing_code(child_uid=CHILD, code="900010"))
        assert message == "Too many pairing attempts. Please try again later."
        return f"10 wrong codes were each \"not found\"; the 11th try is refused with \"{message}\""

    run_case(
        "CASE-039",
        file="backend/tests/cases/test_pairing_service_case_039.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Child enters wrong codes 10 times within 15 minutes.',
        expected='Further attempts fail with “Too many pairing attempts. Please try again later.”',
        body=body,
    )
