
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import pairing_service as pairing

from .case_report import run_case
from .pairing_fixture import CHILD, CHILD2, NOW, PARENT, env, error_of  # noqa: F401


def test_case_047(env):
    db, clock = env

    def body() -> str:
        made = pairing.generate_pairing_code(parent_uid=PARENT, child_name="Ana")
        pairing.redeem_pairing_code(child_uid=CHILD, code=made["code"])
        result = pairing.unpair_child_device(
            parent_uid=PARENT, child_profile_id=made["childProfileId"])
        assert result["status"] == "unpaired"
        child = db.docs.get(f"users/{CHILD}")
        assert child is not None and child["role"] == "child"
        assert child["pairingStatus"] == "not_paired"
        assert "pairedParentId" not in child
        return ("Device removed: the profile is unpaired and the child is no "
                "longer linked, but the child account still exists "
                "(\"Remove Child Device?\" dialog on the emulator figure)")

    run_case(
        "CASE-047",
        file="backend/tests/cases/test_pairing_service_case_047.py",
        code_tested="backend/app/services/pairing_service.py",
        description='Guardian removes the child device and confirms.',
        expected='“Remove Child Device?” appears; the device is removed and the child account is not deleted.',
        body=body,
    )
