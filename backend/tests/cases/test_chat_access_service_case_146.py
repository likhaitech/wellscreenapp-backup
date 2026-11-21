"""CASE-146 - Emergency Access.
Run (from backend): python -m pytest tests/cases/test_chat_access_service_case_146.py -s -q
"""
import datetime as dt  # noqa: F401  (used by some cases)

from app.services import chat_access_service as chat

from .case_report import run_case
from .chat_fixture import NOW, TIKTOK, ask, chat_env  # noqa: F401


def test_case_146(chat_env):
    db, clock = chat_env

    def body() -> str:
        ask(15, "req-0001")
        clock["now"] = NOW + dt.timedelta(minutes=6)  # past the 5-minute wait
        try:
            ask(15, "req-0002")
        except chat.ChatAccessError as error:
            message = str(error)
        else:
            raise AssertionError("second request was accepted")
        assert message == "You already have an unresolved request for this app."
        return f"A second TikTok request while the first is pending is refused: \"{message}\""

    run_case(
        "CASE-146",
        file="backend/tests/cases/test_chat_access_service_case_146.py",
        code_tested="backend/app/services/chat_access_service.py",
        description='Child requests the same app again before a decision.',
        expected='The request is refused with “You already have an unresolved request for this app.”',
        body=body,
    )
