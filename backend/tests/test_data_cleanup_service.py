"""Offline unit tests for Task 9. No Firebase credentials or network needed."""
from __future__ import annotations

import copy
import datetime as dt
import unittest
from unittest.mock import patch

from app.services import data_cleanup_service as cleanup
from google.api_core.exceptions import FailedPrecondition, NotFound


NOW = dt.datetime(2026, 11, 18, 12, tzinfo=dt.timezone.utc)
CUTOFF = NOW - dt.timedelta(days=90)
OLD = CUTOFF - dt.timedelta(seconds=1)
RECENT = CUTOFF + dt.timedelta(seconds=1)
CUTOFF_MS = int(CUTOFF.timestamp() * 1000)
PROJECT = "demo-wellscreen"


class FakeSnapshot:
    def __init__(self, db, path):
        self.reference = FakeReference(db, path)
        self.id = path.rsplit("/", 1)[-1]
        self.update_time = db.versions[path]
        self.data = copy.deepcopy(db.documents[path])

    def to_dict(self):
        return copy.deepcopy(self.data)


class FakeReference:
    def __init__(self, db, path):
        self.db = db
        self.path = path

    def collection(self, name):
        return FakeQuery(self.db, f"{self.path}/{name}")

    def _check(self, option):
        if self.path in self.db.errors:
            raise self.db.errors[self.path]
        if self.path not in self.db.documents:
            raise NotFound("Document was concurrently removed")
        if option != self.db.versions[self.path]:
            raise FailedPrecondition("Document changed")

    def delete(self, *, option):
        self._check(option)
        del self.db.documents[self.path]
        self.db.writes.append(("delete", self.path))

    def update(self, updates, *, option):
        self._check(option)
        self.db.documents[self.path].update(copy.deepcopy(updates))
        self.db.versions[self.path] += 1
        self.db.writes.append(("update", self.path))


class FakeQuery:
    """Minimal ordered, cursor-based Firestore query double."""

    def __init__(self, db, path):
        self.db = db
        self.path = path
        self.fields = ()
        self.filter = None
        self.page_size = None
        self.cursor = None

    def where(self, *, filter):
        result = copy.copy(self)
        result.filter = filter
        return result

    def order_by(self, field):
        result = copy.copy(self)
        result.fields += (field,)
        return result

    def limit(self, size):
        result = copy.copy(self)
        result.page_size = size
        return result

    def start_after(self, snapshot):
        result = copy.copy(self)
        result.cursor = snapshot
        return result

    def _key(self, snapshot):
        return tuple(
            snapshot.id if field == "__name__" else snapshot.data[field]
            for field in self.fields
        )

    def stream(self):
        prefix = self.path + "/"
        paths = [
            path for path in self.db.documents
            if path.startswith(prefix) and "/" not in path[len(prefix):]
        ]
        snapshots = [FakeSnapshot(self.db, path) for path in paths]
        if self.filter is not None:
            assert self.filter.op_string == "<"
            field = self.filter.field_path
            cutoff = self.filter.value
            snapshots = [
                snap for snap in snapshots
                if isinstance(snap.data.get(field), dt.datetime)
                and snap.data[field].utcoffset() is not None
                and snap.data[field] < cutoff
            ]
        snapshots.sort(key=self._key)
        if self.cursor is not None:
            cursor_key = self._key(self.cursor)
            snapshots = [
                snap for snap in snapshots if self._key(snap) > cursor_key
            ]
        if self.page_size is not None:
            snapshots = snapshots[:self.page_size]
        self.db.read_pages += 1
        return iter(snapshots)


class FakeFirestore:
    project = PROJECT

    def __init__(self, documents):
        self.documents = copy.deepcopy(documents)
        self.versions = {path: 1 for path in documents}
        self.writes = []
        self.errors = {}
        self.read_pages = 0

    def collection(self, name):
        return FakeQuery(self, name)

    def write_option(self, *, last_update_time):
        return last_update_time


def sample_data():
    return {
        "system_logs/old_a": {"timestamp": OLD},
        "system_logs/old_b": {"timestamp": OLD},
        "system_logs/old_c": {"timestamp": OLD},
        "system_logs/boundary": {"timestamp": CUTOFF},
        "system_logs/recent": {"timestamp": RECENT},
        "system_logs/unknown": {"timestamp": "invalid"},
        "child_profiles/a": {
            "parentId": "parent",
            "pairingStatus": "connected",
            "latestUsageReport": {"timestampMs": CUTOFF_MS - 1},
            "browsingLog": [
                {"timestampMs": CUTOFF_MS - 1},
                {"timestampMs": CUTOFF_MS},
                {"timestampMs": CUTOFF_MS + 1},
                {"timestampMs": "1"},
                {"timestampMs": True},
                {"timestampMs": 0},
                {},
            ],
            "restrictionLog": [{"timestampMs": CUTOFF_MS - 1}],
            "syncLog": [{"timestampMs": CUTOFF_MS - 1}],
            "smsAlertLog": [{"timestampMs": CUTOFF_MS - 1}, {"status": "unknown"}],
        },
        "child_profiles/b": {"browsingLog": "unknown"},
        "child_profiles/c": {"pairingStatus": "connected"},
        "child_profiles/a/chat_messages/old": {"createdAt": OLD},
        "child_profiles/a/chat_messages/boundary": {"createdAt": CUTOFF},
        "child_profiles/a/chat_messages/unknown": {},
        "child_profiles/b/chat_messages/old": {"createdAt": OLD},
        "child_profiles/c/chat_messages/recent": {"createdAt": RECENT},
        "child_profiles/a/temporary_access_grants/g": {"createdAt": OLD},
        "child_profiles/a/app_time_limits/app": {"updatedAt": OLD},
        "child_profiles/a/access_requests/r": {"createdAt": OLD},
        "users/parent": {"createdAt": OLD},
        "app_rules/parent": {"updatedAt": OLD},
        "notifications/n": {"createdAt": OLD},
        "monitoring_alerts/m": {"createdAt": OLD},
    }


class TestDataCleanupService(unittest.TestCase):
    def setUp(self):
        self.db = FakeFirestore(sample_data())
        self.original = copy.deepcopy(self.db.documents)
        # Force multiple pages, including a page of equal timestamps.
        self.enterContext(patch.object(cleanup, "PAGE_SIZE", 2))
        self.enterContext(patch.object(
            cleanup, "get_firestore_client",
            side_effect=AssertionError("A real Firebase client must never be used"),
        ))

    def run_cleanup(self, **kwargs):
        return cleanup.cleanup_old_data(db=self.db, now=NOW, **kwargs)

    def apply_cleanup(self):
        return self.run_cleanup(dry_run=False, expected_project=PROJECT)

    def test_dry_run_is_read_only_and_counts_expired_history(self):
        report = self.run_cleanup()
        self.assertTrue(report["dry_run"])
        self.assertEqual(report["cutoff_utc"], CUTOFF.isoformat())
        self.assertEqual(report["profiles_scanned"], 3)
        self.assertEqual(report["candidates"], {
            "system_logs": 3, "chat_messages": 2,
            "browsingLog": 1, "restrictionLog": 1,
            "syncLog": 1, "smsAlertLog": 1,
        })
        self.assertFalse(any(report["removed"].values()))
        self.assertEqual(self.db.documents, self.original)
        self.assertEqual(self.db.writes, [])

    def test_apply_deletes_only_allowlisted_expired_history(self):
        report = self.apply_cleanup()
        expected = copy.deepcopy(self.original)
        for path in (
            "system_logs/old_a", "system_logs/old_b", "system_logs/old_c",
            "child_profiles/a/chat_messages/old",
            "child_profiles/b/chat_messages/old",
        ):
            del expected[path]
        profile = expected["child_profiles/a"]
        for field in ("browsingLog", "restrictionLog", "syncLog", "smsAlertLog"):
            profile[field] = profile[field][1:]
        self.assertEqual(self.db.documents, expected)
        self.assertEqual(report["removed"], report["candidates"])
        self.assertEqual(report["concurrent_changes_skipped"], 0)
        self.assertEqual(len(self.db.writes), 6)

    def test_repeated_cleanup_is_idempotent(self):
        self.apply_cleanup()
        writes = list(self.db.writes)
        report = self.apply_cleanup()
        self.assertFalse(any(report["candidates"].values()))
        self.assertFalse(any(report["removed"].values()))
        self.assertEqual(self.db.writes, writes)

    def test_apply_requires_an_explicit_matching_project(self):
        for options in (
            {"dry_run": False},
            {"dry_run": False, "expected_project": "wrong-project"},
        ):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.run_cleanup(**options)
        self.assertEqual(self.db.documents, self.original)
        self.assertEqual(self.db.read_pages, 0)

    def test_concurrent_changes_are_skipped(self):
        self.db.errors["child_profiles/a"] = FailedPrecondition("new sync")
        self.db.errors["system_logs/old_a"] = FailedPrecondition("new write")
        self.db.errors["system_logs/old_b"] = NotFound("removed elsewhere")
        report = self.apply_cleanup()
        self.assertEqual(report["concurrent_changes_skipped"], 3)
        self.assertEqual(report["removed"]["system_logs"], 1)
        self.assertEqual(report["removed"]["browsingLog"], 0)
        self.assertEqual(
            self.db.documents["child_profiles/a"],
            self.original["child_profiles/a"],
        )
        self.assertEqual(report["removed"]["chat_messages"], 2)

    def test_unexpected_firestore_error_is_not_silenced(self):
        self.db.errors["system_logs/old_a"] = RuntimeError("database unavailable")
        with self.assertRaisesRegex(RuntimeError, "database unavailable"):
            self.apply_cleanup()

    def test_timestamp_validation_and_exact_boundary(self):
        for stamp in (None, "invalid", CUTOFF.replace(tzinfo=None), CUTOFF, RECENT):
            with self.subTest(stamp=stamp):
                self.assertFalse(cleanup._expired_timestamp(stamp, CUTOFF))
        self.assertTrue(cleanup._expired_timestamp(OLD, CUTOFF))

    def test_malformed_profile_timestamps_are_preserved(self):
        entries = [None, {}, {"timestampMs": True}, {"timestampMs": -1},
                   {"timestampMs": 1.5}, {"timestampMs": "1"},
                   {"timestampMs": CUTOFF_MS}]
        updates, counts = cleanup._profile_updates(
            {"browsingLog": entries}, CUTOFF_MS
        )
        self.assertEqual(updates, {})
        self.assertEqual(counts, {})

    def test_invalid_now_and_dry_run_fail_before_database_access(self):
        with self.assertRaises(ValueError):
            cleanup.cleanup_old_data(db=self.db, now=NOW.replace(tzinfo=None))
        with self.assertRaises(TypeError):
            self.run_cleanup(dry_run="false")
        self.assertEqual(self.db.read_pages, 0)

    def test_cli_requires_project_id_for_apply(self):
        with patch("sys.argv", ["cleanup", "--apply"]):
            with patch.object(cleanup, "cleanup_old_data") as mocked:
                with self.assertRaises(SystemExit) as exc:
                    cleanup.main()
                self.assertEqual(exc.exception.code, 2)
                mocked.assert_not_called()


if __name__ == "__main__":
    unittest.main()
