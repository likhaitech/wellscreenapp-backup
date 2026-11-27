"""Shared setup for the alert test cases: the real monitoring alerts service
with Firestore, push and SMS replaced by recorders (no Firebase project)."""
from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app.services import monitoring_alerts_service as svc

NOW = datetime(2026, 11, 22, 12, tzinfo=timezone.utc)


@pytest.fixture
def alerts_env(monkeypatch):
    clock = [NOW]
    profile = {
        "parentId": "parent-1",
        "childAccountId": "child-1",
        "childDisplayName": "Ana",
        "pairingStatus": "connected",
        "lastSeenAt": clock[0],
    }
    records = {}
    profile_ref = Mock()
    alerts = Mock()

    def alert_document(alert_id):
        ref = Mock()

        def create(data):
            if alert_id in records:
                raise svc.AlreadyExists("Duplicate alert")
            records[alert_id] = dict(data)

        ref.create.side_effect = create
        ref.update.side_effect = lambda data: records[alert_id].update(data)
        return ref

    alerts.document.side_effect = alert_document
    profile_ref.collection.return_value = alerts
    profile_ref.update.side_effect = lambda data: profile.update(data)
    snapshot = SimpleNamespace(id="profile-1", to_dict=lambda: dict(profile),
                               reference=profile_ref, exists=True)
    profile_ref.get.return_value = snapshot
    profiles = Mock()
    profiles.document.return_value = profile_ref
    profiles.where.return_value.stream.side_effect = lambda: (
        [snapshot] if profile["pairingStatus"] == "connected" else [])
    db = Mock()
    db.collection.return_value = profiles
    push = Mock(return_value={"status": "sent", "message_id": "push-1"})
    sms = Mock(return_value={"status": "accepted"})
    monkeypatch.setattr(svc, "get_firestore_client", lambda: db)
    monkeypatch.setattr(svc, "_utcnow", lambda: clock[0])
    monkeypatch.setattr(svc, "send_alert_notification", push)
    monkeypatch.setattr(svc, "_send_sms", sms)
    return SimpleNamespace(clock=clock, profile=profile, records=records,
                           push=push, sms=sms)
