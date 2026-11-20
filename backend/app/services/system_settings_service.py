from __future__ import annotations

from typing import Any

from firebase_admin import firestore

from .firebase_service import get_firestore_client


# Manuscript Ch. III: 6 and below 1h, 7-12 2h, 13-15 3h. Possible-risk
# sites are blocked for the youngest group and reviewed by the guardian
# for older children. Read by the guardian and child apps.
DEFAULT_SYSTEM_SETTINGS = {
    "goal_minutes_6_and_below": 60,
    "goal_minutes_7_12": 120,
    "goal_minutes_13_15": 180,
    "risky_sites_6_and_below": "block",
    "risky_sites_7_12": "review",
    "risky_sites_13_15": "review",
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