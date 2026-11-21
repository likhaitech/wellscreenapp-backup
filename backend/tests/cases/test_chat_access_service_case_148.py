"""CASE-148 - Emergency Access.
Run (from backend): python -m pytest tests/cases/test_chat_access_service_case_148.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import chat_access_service as chat

from .case_report import run_case
from .chat_fixture import NOW, TIKTOK, ask, chat_env  # noqa: F401


def test_case_148(chat_env):
    db, clock = chat_env

    def body() -> str:
        ask(15)
        decided = chat.respond_to_request(parent_uid="parent-1", profile_id="profile-1",
                                          request_id="req-0001", approve=True,
                                          approved_minutes=20)
        assert decided == {"status": "approved_pending_activation", "approvedMinutes": 20}
        active = chat.activate_grant(child_uid="child-1", profile_id="profile-1",
                                     package_name=TIKTOK)
        grant = db.docs[f"child_profiles/profile-1/temporary_access_grants/{TIKTOK}"]
        minutes = (active["expiresAt"] - grant["activatedAt"]).total_seconds() / 60
        assert active["status"] == "active" and minutes == 20
        return ("Child asked for 15 min, the guardian changed it to 20 and "
                "approved; TikTok opens for exactly 20 minutes, then the chat "
                "shows \"Access expired\"")

    run_case(
        "CASE-148",
        file="backend/tests/cases/test_chat_access_service_case_148.py",
        code_tested="backend/app/services/chat_access_service.py",
        description='Guardian modifies the time and approves.',
        expected='The app opens for the approved time, then shows “Access expired”.',
        body=body,
    )
