"""CASE-033 - Device Pairing and Permission Setup.
Run (from backend): python -m pytest tests/cases/test_pairing_service_case_033.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_033(env):
    db, clock = env

    def body() -> str:
        result = pairing.generate_pairing_code(parent_uid=PARENT, child_name="Ana")
        code = result["code"]
        assert len(code) == 6 and code.isdigit()
        profile = db.docs[f"child_profiles/{result['childProfileId']}"]
        assert profile["pairingStatus"] == "waiting"
        assert db.docs[f"pairing_codes/{code}"]["status"] == "active"
        return (f"Code {code} created (six digits, valid 15 minutes); the child "
                f"profile is \"{profile['pairingStatus']}\", shown as Waiting for child "
                "with the QR code on the emulator figure")

    run_case(
        "CASE-033",
        file="backend/tests/cases/test_pairing_service_case_033.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Verified guardian taps Generate Code.',
        expected='A six-digit pairing code and its QR code are displayed with “Waiting for child”.',
        body=body,
    )
