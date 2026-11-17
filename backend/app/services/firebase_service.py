from __future__ import annotations

import os
import threading
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials, firestore
from google.auth.credentials import AnonymousCredentials


_BACKEND_DIR = Path(__file__).resolve().parents[2]
_DEFAULT_SERVICE_ACCOUNT = _BACKEND_DIR / "firebase-service-account.json"

_init_lock = threading.Lock()


class EmulatorCredential(credentials.Base):
    """Anonymous credentials for local Firestore Emulator testing."""

    def get_credential(self):
        return AnonymousCredentials()


def initialize_firebase() -> firebase_admin.App:
    """Initialize Firebase Admin once.

    Supports local Firestore Emulator testing and production Firebase.
    """

    if firebase_admin._apps:
        return firebase_admin.get_app()

    with _init_lock:
        if firebase_admin._apps:
            return firebase_admin.get_app()

        # LOCAL TESTING: Firestore Emulator
        emulator_host = os.getenv("FIRESTORE_EMULATOR_HOST")

        if emulator_host:
            project_id = (
                os.getenv("GOOGLE_CLOUD_PROJECT")
                or os.getenv("GCLOUD_PROJECT")
                or "wellscreen-rules-test"
            )

            emulator_credential = EmulatorCredential()

            return firebase_admin.initialize_app(
                emulator_credential,
                options={"projectId": project_id},
            )

        # PRODUCTION: Service account credentials
        configured_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")

        service_account_path = (
            Path(configured_path).expanduser().resolve()
            if configured_path
            else _DEFAULT_SERVICE_ACCOUNT
        )

        if service_account_path.exists():
            credential = credentials.Certificate(
                str(service_account_path)
            )

            return firebase_admin.initialize_app(credential)

        # PRODUCTION: Application Default Credentials
        try:
            return firebase_admin.initialize_app()

        except Exception as exc:
            raise RuntimeError(
                "Firebase Admin credentials were not found. "
                "Place the Firebase service-account JSON at "
                "backend/firebase-service-account.json "
                "or set FIREBASE_SERVICE_ACCOUNT_PATH."
            ) from exc


def get_firestore_client():
    initialize_firebase()
    return firestore.client()


def get_auth_module():
    initialize_firebase()
    return auth
