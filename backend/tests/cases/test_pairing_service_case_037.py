"""CASE-037 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_037.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_037(env):
    db, clock = env

    def body() -> str:
        made = pairing.generate_pairing_code(parent_uid=PARENT, child_name="Ana")
        result = pairing.redeem_pairing_code(child_uid=CHILD, code=made["code"])
        assert result["status"] == "connected"
        profile = db.docs[f"child_profiles/{made['childProfileId']}"]
        assert profile["pairingStatus"] == "connected"
        assert profile["childAccountId"] == CHILD
        assert db.docs[f"users/{CHILD}"]["pairedParentId"] == PARENT
        return (f"Code {made['code']} redeemed: status connected, the child "
                "profile under the guardian now holds the child account "
                "(\"Device Connected Successfully!\" on the emulator figure)")

    run_case(
        "CASE-037",
        file="backend/tests/cases/test_pairing_service_case_037.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Child types a valid pairing code.',
        expected='“Device Connected Successfully!” is displayed and the child appears under the guardian.',
        body=body,
    )
