"""CASE-145 - Emergency Access.
Run (from backend): python -m pytest tests/cases/test_chat_access_service_case_145.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import chat_access_service as chat

from .case_report import run_case
from .chat_fixture import NOW, TIKTOK, ask, chat_env  # noqa: F401


def test_case_145(chat_env):
    db, clock = chat_env

    def body() -> str:
        result = ask(15)
        assert result["status"] == "pending"
        saved = db.docs["child_profiles/profile-1/access_requests/req-0001"]
        assert saved["requestedMinutes"] == 15 and saved["appName"] == "TikTok"
        return ("The request for 15 min of TikTok was saved as pending for the "
                "guardian (\"App access request sent. Your parent will be notified.\" "
                "on the emulator figure)")

    run_case(
        "CASE-145",
        file="backend/tests/cases/test_chat_access_service_case_145.py",
        code_tested="backend/app/services/chat_access_service.py",
        description='Child requests time for a blocked app in Chat.',
        expected='“App access request sent. Your parent will be notified.” is displayed.',
        body=body,
    )
