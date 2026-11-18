"""What the live backend exposes without credentials."""
from __future__ import annotations

import importlib

from fastapi.testclient import TestClient

import app.main as main_module
from app.main import app

client = TestClient(app)


def test_api_docs_are_off_by_default():
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404, path


def test_api_docs_can_be_turned_on_for_development(monkeypatch):
    monkeypatch.setenv("WELLSCREEN_ENABLE_API_DOCS", "1")
    try:
        reloaded = importlib.reload(main_module)
        dev_client = TestClient(reloaded.app)
        assert dev_client.get("/openapi.json").status_code == 200
    finally:
        monkeypatch.delenv("WELLSCREEN_ENABLE_API_DOCS", raising=False)
        importlib.reload(main_module)


def test_chat_sweep_rejects_wrong_or_missing_secret(monkeypatch):
    monkeypatch.setenv("CHAT_CRON_SECRET", "right-secret")
    url = "/internal/chat/notifications/sweep"
    assert client.post(url).status_code == 403
    assert (
        client.post(url, headers={"X-Chat-Cron-Secret": "wrong"}).status_code
        == 403
    )


def test_chat_sweep_accepts_the_right_secret(monkeypatch):
    from app.routes import parent_child_chat

    monkeypatch.setenv("CHAT_CRON_SECRET", "right-secret")
    monkeypatch.setattr(
        parent_child_chat, "sweep_chat_notifications", lambda: {"sent": 0}
    )
    response = client.post(
        "/internal/chat/notifications/sweep",
        headers={"X-Chat-Cron-Secret": "right-secret"},
    )
    assert response.status_code == 200
