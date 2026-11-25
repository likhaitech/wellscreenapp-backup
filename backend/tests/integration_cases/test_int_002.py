"""INT-002 - Profile Management Module -> Device Pairing and Permission Setup Module.
Guardian creates a child profile; the new profile becomes available for pairing.
Run (from backend): python -m pytest tests/integration_cases/test_int_002.py -s -q -p no:anyio
"""
from app.services import pairing_service as pairing

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, system  # noqa: F401


def test_int_002(system):
    db = system.db

    def body() -> str:
        # Module 1 - Profile Management: the guardian adds the child "Ana".
        made = pairing.generate_pairing_code(parent_uid=GUARDIAN, child_name="Ana")
        profile = db.docs[f"child_profiles/{made['childProfileId']}"]
        assert profile["parentId"] == GUARDIAN and profile["name"] == "Ana"
        assert profile["pairingStatus"] == "waiting"
        code = db.docs[f"pairing_codes/{made['code']}"]
        assert code["childId"] == made["childProfileId"] and code["status"] == "active"
        assert len(made["code"]) == 6 and made["code"].isdigit()

        # Module 2 - Device Pairing: the child's phone pairs to that profile.
        result = pairing.redeem_pairing_code(child_uid=CHILD, code=made["code"])
        assert result["status"] == "connected"
        assert db.docs[f"child_profiles/{made['childProfileId']}"]["childAccountId"] == CHILD
        return (f"The child profile \"Ana\" was created under the guardian (status "
                f"waiting) with 6-digit code {made['code']}; the child phone then paired "
                "to that same profile (status connected)")

    run_case(
        "INT-002",
        file="backend/tests/integration_cases/test_int_002.py",
        code_tested="backend/app/services/pairing_service.py (profile + pairing)",
        description="Create a child profile (Profile Management -> Device Pairing and Permission Setup).",
        expected="The new child profile becomes available for pairing with a monitored Android device.",
        body=body,
    )
