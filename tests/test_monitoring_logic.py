"""Run: python -m unittest discover -s tests -v (from patch root).

Tests the actual module against local fakes; Firebase/Twilio credentials aren't needed.
"""
from __future__ import annotations

import importlib.util
import os
import sys
import types
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


class AlreadyExists(Exception):
    pass


def load_service():
    for name in ("google", "google.api_core", "google.api_core.exceptions",
                 "app", "app.services", "app.services.firebase_service",
                 "app.services.notification_service"):
        if name not in sys.modules:
            sys.modules[name] = types.ModuleType(name)
    sys.modules["google.api_core.exceptions"].AlreadyExists = AlreadyExists
    sys.modules["google.api_core.exceptions"].Conflict = AlreadyExists
    sys.modules["app.services.firebase_service"].get_firestore_client = lambda: None
    sys.modules["app.services.notification_service"].send_alert_notification = lambda **kw: {"status": "sent"}
    path = (Path(__file__).resolve().parents[1] / "backend/app/services/monitoring_alerts_service.py")
    spec = importlib.util.spec_from_file_location("app.services.monitoring_alerts_service", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FakeAlertRef:
    def __init__(self, database, key):
        self.db, self.key = database, key

    def create(self, value):
        if self.key in self.db.alerts:
            raise AlreadyExists()
        self.db.alerts[self.key] = value.copy()

    def update(self, value):
        self.db.alerts[self.key].update(value)


class FakeAlertCollection:
    def __init__(self, database, key):
        self.db, self.key = database, key

    def document(self, name):
        return FakeAlertRef(self.db, (self.key, name))


class FakeSnapshot:
    def __init__(self, database, identity, value):
        self.db, self.id, self.value = database, identity, value
        self.reference = self

    def to_dict(self):
        return self.value

    def get(self):
        return self

    def update(self, values):
        self.value.update(values)

    def collection(self, name):
        return FakeAlertCollection(self.db, (self.id, name))


class FakeChildProfiles:
    def __init__(self, database):
        self.db = database

    def where(self, field, op, value):
        return self

    def stream(self):
        return self.db.children.values()

    def document(self, identity):
        return self.db.children[identity]


class FakeDatabase:
    def __init__(self):
        self.children = {}
        self.alerts = {}

    def collection(self, name):
        assert name == "child_profiles"
        return FakeChildProfiles(self)


class MonitoringTests(unittest.TestCase):
    def setUp(self):
        self.module = load_service()
        self.db = FakeDatabase()
        self.module.get_firestore_client = lambda: self.db
        self.sent = []
        self.sms = []
        self.module._push = lambda **kw: (self.sent.append(kw) or {"status": "sent"})
        self.module._send_sms = lambda **kw: (self.sms.append(kw) or {"status": "accepted"})
        self.previous = os.environ.get("MONITORING_MISSING_TIMEOUT_MINUTES")
        os.environ["MONITORING_MISSING_TIMEOUT_MINUTES"] = "90"

    def tearDown(self):
        if self.previous is None:
            os.environ.pop("MONITORING_MISSING_TIMEOUT_MINUTES", None)
        else:
            os.environ["MONITORING_MISSING_TIMEOUT_MINUTES"] = self.previous

    def add_child(self, identity, minutes_ago):
        seen = None if minutes_ago is None else datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
        child = {"pairingStatus": "connected", "parentId": "parent123",
                 "deviceName": "Example Child Device", "lastSeenAt": seen}
        self.db.children[identity] = FakeSnapshot(self.db, identity, child)

    def test_never_checked_in_does_not_trigger_alert(self):
        self.add_child("a", None)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 0)

    def test_recent_connection_does_not_trigger_alert(self):
        self.add_child("a", 20)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 0)

    def test_missing_generates_single_alert_even_after_repeated_sweep(self):
        self.add_child("a", 180)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 1)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 0)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(len(self.sms), 1)
        self.assertIn("may be offline", self.sent[0]["message"])
        self.assertEqual(len(self.db.alerts), 1)

    def test_new_gap_after_reconnection_is_new_incident(self):
        self.add_child("a", 180)
        self.module.sweep_missing_heartbeats()
        self.db.children["a"].value["lastSeenAt"] = datetime.now(timezone.utc)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 0)
        self.db.children["a"].value["lastSeenAt"] -= timedelta(minutes=180)
        self.assertEqual(self.module.sweep_missing_heartbeats()["newAlerts"], 1)
        self.assertEqual(len(self.db.alerts), 2)

    def test_duplicate_child_event_is_not_sent_twice(self):
        self.add_child("a", 10)
        self.db.children["a"].value["childAccountId"] = "child123"
        event = {"eventId": "event_2026_001", "type": "screen_time_limit_exceeded",
                 "timestampMs": int(datetime.now(timezone.utc).timestamp() * 1000),
                 "subject": "com.example.game", "label": "Example Game"}
        for _ in range(2):
            result = self.module.accept_child_events(
                child_uid="child123", profile_id="a", events=[event],
            )
            self.assertEqual(result["acceptedEventIds"], [event["eventId"]])
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(len(self.sms), 0)  # Sent via FCM; SMS is fallback.

    def test_unpaired_user_cannot_submit_child_events(self):
        self.add_child("a", 10)
        self.db.children["a"].value["childAccountId"] = "child123"
        with self.assertRaises(PermissionError):
            self.module.accept_child_events(child_uid="attacker", profile_id="a", events=[{}])

    def test_timeout_has_60_minute_floor(self):
        os.environ["MONITORING_MISSING_TIMEOUT_MINUTES"] = "5"
        self.assertEqual(self.module._timeout_minutes(), 60)


if __name__ == '__main__':
    unittest.main()
