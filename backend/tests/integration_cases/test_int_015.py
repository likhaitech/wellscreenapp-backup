
import datetime as dt

from app.services import chat_access_service as chat

from ..cases.case_report import run_case
from .int_fixture import CHILD, GUARDIAN, TIKTOK, pair_child, system  # noqa: F401


def test_int_015(system):
    db = system.db

    def body() -> str:
        profile_id = pair_child(system)

        db.docs[f"app_rules/{GUARDIAN}"] = {"rules": [
            {"packageName": TIKTOK, "appName": "TikTok", "restrictEnabled": True}]}


        sent = chat.submit_access_request(child_uid=CHILD, profile_id=profile_id,
                                          request_id="req-0001", package_name=TIKTOK,
                                          requested_minutes=15)
        assert sent == {"requestId": "req-0001", "status": "pending"}


        decided = chat.respond_to_request(parent_uid=GUARDIAN, profile_id=profile_id,
                                          request_id="req-0001", approve=True,
                                          approved_minutes=15)
        assert decided["status"] == "approved_pending_activation"


        active = chat.activate_grant(child_uid=CHILD, profile_id=profile_id, package_name=TIKTOK)
        grant = db.docs[f"child_profiles/{profile_id}/temporary_access_grants/{TIKTOK}"]
        minutes = (active["expiresAt"] - grant["activatedAt"]) / dt.timedelta(minutes=1)
        assert active["status"] == "active" and minutes == 15
        assert db.docs[f"child_profiles/{profile_id}/access_requests/req-0001"]["status"] == "active"
        return ("The child asked for 15 minutes of the blocked TikTok in Chat, the guardian "
                "approved, and TikTok is unlocked on the child phone for exactly 15 minutes")

    run_case(
        "INT-015",
        file="backend/tests/integration_cases/test_int_015.py",
        code_tested="backend/app/services/chat_access_service.py",
        description="Child requests app time through Chat (Emergency Access -> Rule Management and Restriction).",
        expected="The guardian approves the request in Chat and the app opens on the child device for the approved time.",
        body=body,
    )
