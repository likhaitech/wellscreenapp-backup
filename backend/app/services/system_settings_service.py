from __future__ import annotations

from typing import Any

from firebase_admin import firestore

from .firebase_service import get_firestore_client


# Read by every phone. "1.0.0" lets every released version run.
DEFAULT_SYSTEM_SETTINGS = {
    "minimum_app_version": "1.0.0",
    "maintenance_message": "",
}


def _settings_document():
    db = get_firestore_client()

    return (
        db.collection("system_settings")
        .document("global")
    )


def get_system_settings() -> dict[str, Any]:
    document = _settings_document().get()

    settings = dict(DEFAULT_SYSTEM_SETTINGS)

    if document.exists:
        stored_settings = document.to_dict() or {}

        for key in DEFAULT_SYSTEM_SETTINGS:
            if key in stored_settings:
                settings[key] = stored_settings[key]

        settings["updated_at"] = stored_settings.get("updated_at")
        settings["updated_by"] = stored_settings.get("updated_by")
    else:
        settings["updated_at"] = None
        settings["updated_by"] = None

    return settings


def update_system_settings(
    changes: dict[str, Any],
    *,
    updated_by: str,
) -> dict[str, Any]:

    allowed_changes = {
        key: value
        for key, value in changes.items()
        if key in DEFAULT_SYSTEM_SETTINGS
    }

    if allowed_changes:
        _settings_document().set(
            {
                **allowed_changes,
                "updated_at": firestore.SERVER_TIMESTAMP,
                "updated_by": updated_by,
            },
            merge=True,
        )

    return get_system_settings()