"""Tests for app/services/system_settings_service.py - backs GET/PATCH
/admin/settings. The important behaviors here are: unknown settings never
get filtered into what's read back (whatever's in DEFAULT_SYSTEM_SETTINGS
wins), a stored document only overrides the keys it actually contains, and
update_system_settings silently drops any key that isn't a recognized
setting rather than writing arbitrary fields to Firestore. Firestore is
mocked throughout - get_firestore_client is patched.
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from firebase_admin import firestore

from app.services import system_settings_service as svc


def _fake_db_with_doc(*, exists: bool, data: dict | None = None):
    doc_snapshot = MagicMock()
    doc_snapshot.exists = exists
    doc_snapshot.to_dict.return_value = data or {}

    fake_db = MagicMock()
    fake_db.collection.return_value.document.return_value.get.return_value = doc_snapshot
    return fake_db, doc_snapshot


class TestGetSystemSettings:
    def test_returns_hardcoded_defaults_when_no_document_exists(self):
        fake_db, _ = _fake_db_with_doc(exists=False)

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.get_system_settings()

        for key, value in svc.DEFAULT_SYSTEM_SETTINGS.items():
            assert result[key] == value
        assert result["updated_at"] is None
        assert result["updated_by"] is None

    def test_stored_document_overrides_only_the_keys_it_contains(self):
        fake_db, _ = _fake_db_with_doc(
            exists=True,
            data={
                "goal_minutes_7_12": 90,
                "updated_at": "2024-01-01",
                "updated_by": "admin-1",
            },
        )

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.get_system_settings()

        assert result["goal_minutes_7_12"] == 90
        # Untouched keys keep their hardcoded default.
        assert result["risky_sites_7_12"] == svc.DEFAULT_SYSTEM_SETTINGS["risky_sites_7_12"]
        assert result["updated_at"] == "2024-01-01"
        assert result["updated_by"] == "admin-1"

    def test_unknown_keys_in_stored_document_are_ignored(self):
        # A stale/legacy field in Firestore must not leak into the API
        # response as an unexpected setting.
        fake_db, _ = _fake_db_with_doc(
            exists=True,
            data={"some_removed_setting": True},
        )

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.get_system_settings()

        assert "some_removed_setting" not in result


class TestUpdateSystemSettings:
    def test_only_recognized_keys_are_written(self):
        fake_db, _ = _fake_db_with_doc(exists=False)

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.update_system_settings(
                {
                    "goal_minutes_7_12": 120,
                    "not_a_real_setting": "sneaky",
                },
                updated_by="admin-1",
            )

        written = fake_db.collection.return_value.document.return_value.set.call_args[0][0]
        assert written["goal_minutes_7_12"] == 120
        assert "not_a_real_setting" not in written
        assert written["updated_by"] == "admin-1"
        assert written["updated_at"] is firestore.SERVER_TIMESTAMP

    def test_write_uses_merge_true_so_other_settings_survive(self):
        fake_db, _ = _fake_db_with_doc(exists=False)

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.update_system_settings(
                {"risky_sites_7_12": "block"}, updated_by="admin-1"
            )

        call = fake_db.collection.return_value.document.return_value.set.call_args
        assert call.kwargs.get("merge") is True

    def test_no_recognized_changes_skips_the_write_entirely(self):
        # If every key in `changes` is unrecognized, there's nothing to
        # persist - update_system_settings should not call .set() at all,
        # just return the current settings unchanged.
        fake_db, _ = _fake_db_with_doc(exists=False)

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.update_system_settings({"nonsense": 1}, updated_by="admin-1")

        fake_db.collection.return_value.document.return_value.set.assert_not_called()

    def test_returns_the_settings_after_the_write(self):
        fake_db, doc_snapshot = _fake_db_with_doc(exists=True, data={})
        # Simulate the write actually landing: after .set() is called, a
        # subsequent .get() would see the new value. We just assert the
        # function calls get_system_settings() again by checking the
        # returned dict has the change applied given the doc mock reflects
        # it.
        doc_snapshot.to_dict.return_value = {
            "goal_minutes_7_12": 60,
            "updated_by": "admin-2",
        }

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.update_system_settings(
                {"goal_minutes_7_12": 60}, updated_by="admin-2"
            )

        assert result["goal_minutes_7_12"] == 60
        assert result["updated_by"] == "admin-2"
