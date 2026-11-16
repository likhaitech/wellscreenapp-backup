"""Tests for app/services/firebase_service.py - the one place every other
backend service/route ultimately calls through to get a Firebase app,
Firestore client, or auth module. Every other test file in this suite
mocks this module out entirely (patching get_firestore_client /
initialize_firebase directly) precisely because this file's own job is to
decide *how* Firebase gets initialized - from an explicit
FIREBASE_SERVICE_ACCOUNT_PATH, the default
backend/firebase-service-account.json path, or Application Default
Credentials - and that branching logic deserves its own coverage.

firebase_admin.initialize_app and credentials.Certificate are both mocked,
so no real Firebase project or network call is involved. firebase_admin's
global `_apps` registry is saved/restored around each test since
initialize_firebase()'s very first check (`if firebase_admin._apps`)
reads real global module state that would otherwise leak between tests.
"""
from __future__ import annotations

import threading
import time
from unittest.mock import MagicMock, patch

import pytest

import firebase_admin

from app.services import firebase_service as svc


@pytest.fixture(autouse=True)
def clean_firebase_apps(monkeypatch):
    """Isolate Firebase app registry and production credential tests."""

    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)

    original = dict(firebase_admin._apps)
    firebase_admin._apps.clear()

    try:
        yield
    finally:
        firebase_admin._apps.clear()
        firebase_admin._apps.update(original)


class TestInitializeFirebase:
    def test_returns_existing_app_without_reinitializing(self):
        fake_app = MagicMock()
        firebase_admin._apps["[DEFAULT]"] = fake_app

        with patch.object(svc.firebase_admin, "initialize_app") as mock_init, \
             patch.object(svc.firebase_admin, "get_app", return_value=fake_app) as mock_get:
            result = svc.initialize_firebase()

        mock_init.assert_not_called()
        mock_get.assert_called_once()
        assert result is fake_app

    def test_uses_default_service_account_path_when_it_exists(self, tmp_path, monkeypatch):
        fake_service_account = tmp_path / "firebase-service-account.json"
        fake_service_account.write_text("{}")
        monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)
        monkeypatch.setattr(svc, "_DEFAULT_SERVICE_ACCOUNT", fake_service_account)

        fake_credential = MagicMock()
        fake_app = MagicMock()

        with patch.object(
            svc.credentials, "Certificate", return_value=fake_credential
        ) as mock_certificate, patch.object(
            svc.firebase_admin, "initialize_app", return_value=fake_app
        ) as mock_init:
            result = svc.initialize_firebase()

        mock_certificate.assert_called_once_with(str(fake_service_account))
        mock_init.assert_called_once_with(fake_credential)
        assert result is fake_app

    def test_env_var_path_takes_priority_over_default_path(self, tmp_path, monkeypatch):
        default_path = tmp_path / "default.json"
        default_path.write_text("{}")  # exists, but should be ignored
        configured_path = tmp_path / "configured.json"
        configured_path.write_text("{}")

        monkeypatch.setattr(svc, "_DEFAULT_SERVICE_ACCOUNT", default_path)
        monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT_PATH", str(configured_path))

        with patch.object(
            svc.credentials, "Certificate", return_value=MagicMock()
        ) as mock_certificate, patch.object(
            svc.firebase_admin, "initialize_app", return_value=MagicMock()
        ):
            svc.initialize_firebase()

        mock_certificate.assert_called_once_with(str(configured_path))

    def test_falls_back_to_application_default_credentials_when_no_file_found(
        self, tmp_path, monkeypatch
    ):
        missing_path = tmp_path / "does-not-exist.json"
        monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)
        monkeypatch.setattr(svc, "_DEFAULT_SERVICE_ACCOUNT", missing_path)

        fake_app = MagicMock()

        with patch.object(svc.credentials, "Certificate") as mock_certificate, \
             patch.object(svc.firebase_admin, "initialize_app", return_value=fake_app) as mock_init:
            result = svc.initialize_firebase()

        mock_certificate.assert_not_called()
        # Called with no credential argument - i.e. Application Default
        # Credentials, matching the try/except fallback branch.
        mock_init.assert_called_once_with()
        assert result is fake_app

    def test_concurrent_calls_only_initialize_once(self, tmp_path, monkeypatch):
        # FIX regression test: FastAPI runs sync dependencies (require_admin/
        # require_user, both of which call this) in a real OS thread pool,
        # not just interleaved async tasks. Before the lock, two threads
        # could both pass the unguarded `if firebase_admin._apps` check
        # while empty and both reach initialize_app() - the loser raising
        # ValueError("The default Firebase app already exists") outside any
        # try/except in the callers. This drives two real threads through
        # initialize_firebase() at once, with initialize_app() deliberately
        # slowed down to widen that race window, and asserts it only ever
        # runs once.
        fake_service_account = tmp_path / "firebase-service-account.json"
        fake_service_account.write_text("{}")
        monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)
        monkeypatch.setattr(svc, "_DEFAULT_SERVICE_ACCOUNT", fake_service_account)

        fake_app = MagicMock()
        call_count = 0
        start_barrier = threading.Barrier(2)

        def slow_initialize_app(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            time.sleep(0.05)
            firebase_admin._apps["[DEFAULT]"] = fake_app
            return fake_app

        results: list = []
        errors: list = []

        def worker():
            start_barrier.wait()
            try:
                results.append(svc.initialize_firebase())
            except Exception as exc:  # pragma: no cover - failure path
                errors.append(exc)

        with patch.object(svc.credentials, "Certificate", return_value=MagicMock()), \
             patch.object(svc.firebase_admin, "initialize_app", side_effect=slow_initialize_app):
            threads = [threading.Thread(target=worker) for _ in range(2)]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=5)

        assert errors == []
        assert call_count == 1
        assert results == [fake_app, fake_app]

    def test_missing_credentials_raise_a_clear_runtime_error(self, tmp_path, monkeypatch):
        missing_path = tmp_path / "does-not-exist.json"
        monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)
        monkeypatch.setattr(svc, "_DEFAULT_SERVICE_ACCOUNT", missing_path)

        with patch.object(
            svc.firebase_admin,
            "initialize_app",
            side_effect=ValueError("no default credentials"),
        ):
            with pytest.raises(RuntimeError) as exc_info:
                svc.initialize_firebase()

        assert "firebase-service-account.json" in str(exc_info.value)


class TestGetFirestoreClientAndAuthModule:
    def test_get_firestore_client_initializes_first(self):
        with patch.object(svc, "initialize_firebase") as mock_init, \
             patch.object(svc.firestore, "client", return_value="fake-client") as mock_client:
            result = svc.get_firestore_client()

        mock_init.assert_called_once()
        mock_client.assert_called_once()
        assert result == "fake-client"

    def test_get_auth_module_initializes_first_and_returns_the_auth_module(self):
        with patch.object(svc, "initialize_firebase") as mock_init:
            result = svc.get_auth_module()

        mock_init.assert_called_once()
        assert result is svc.auth
