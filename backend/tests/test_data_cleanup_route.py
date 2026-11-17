"""Offline API tests for the scheduled retention endpoint."""
from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import data_cleanup as route


PATH = "/internal/maintenance/cleanup"
TOKEN = "test-only-token-0123456789-0123456789"
PROJECT = "demo-wellscreen"


class TestDataCleanupRoute(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(os.environ, {
            "WELLSCREEN_CLEANUP_TOKEN": TOKEN,
            "WELLSCREEN_CLEANUP_PROJECT_ID": PROJECT,
            "WELLSCREEN_CLEANUP_APPLY": "false",
            "FIRESTORE_EMULATOR_HOST": "",
        }))
        self.cleanup = self.enterContext(patch.object(
            route, "cleanup_old_data",
            return_value={
                "project_id": PROJECT,
                "dry_run": True,
                "removed": {"system_logs": 0},
                "concurrent_changes_skipped": 0,
            },
        ))
        app = FastAPI()
        app.include_router(route.router)
        self.client = self.enterContext(TestClient(app))
        self.headers = {"X-WellScreen-Cleanup-Token": TOKEN}

    def post(self, **kwargs):
        return self.client.post(PATH, headers=self.headers, **kwargs)

    def test_valid_token_runs_dry_run(self):
        response = self.post()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["dry_run"])
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.cleanup.assert_called_once_with(
            dry_run=True, expected_project=PROJECT
        )

    def test_missing_apply_setting_defaults_to_dry_run(self):
        os.environ.pop("WELLSCREEN_CLEANUP_APPLY")
        self.assertEqual(self.post().status_code, 200)
        self.cleanup.assert_called_once_with(
            dry_run=True, expected_project=PROJECT
        )

    def test_missing_token_rejected(self):
        self.assertEqual(self.client.post(PATH).status_code, 401)
        self.cleanup.assert_not_called()

    def test_wrong_token_rejected(self):
        response = self.client.post(
            PATH, headers={"X-WellScreen-Cleanup-Token": "wrong"}
        )
        self.assertEqual(response.status_code, 401)
        self.cleanup.assert_not_called()

    def test_unconfigured_or_weak_secret_rejected(self):
        for token in ("", "too-short"):
            with self.subTest(token=token):
                os.environ["WELLSCREEN_CLEANUP_TOKEN"] = token
                self.assertEqual(self.post().status_code, 503)
        self.cleanup.assert_not_called()

    def test_missing_project_rejected(self):
        os.environ.pop("WELLSCREEN_CLEANUP_PROJECT_ID")
        self.assertEqual(self.post().status_code, 503)
        self.cleanup.assert_not_called()

    def test_invalid_apply_setting_rejected(self):
        os.environ["WELLSCREEN_CLEANUP_APPLY"] = "yes"
        self.assertEqual(self.post().status_code, 503)
        self.cleanup.assert_not_called()

    def test_request_cannot_override_project_or_deletion_mode(self):
        response = self.post(
            params={"dry_run": "false", "project_id": "other"},
            json={"dry_run": False, "retention_days": 0, "project_id": "other"},
        )
        self.assertEqual(response.status_code, 200)
        self.cleanup.assert_called_once_with(
            dry_run=True, expected_project=PROJECT
        )

    def test_apply_only_when_explicitly_enabled_by_server(self):
        os.environ["WELLSCREEN_CLEANUP_APPLY"] = "true"
        self.assertEqual(self.post().status_code, 200)
        self.cleanup.assert_called_once_with(
            dry_run=False, expected_project=PROJECT
        )

    def test_emulator_cannot_target_non_demo_project(self):
        os.environ["FIRESTORE_EMULATOR_HOST"] = "127.0.0.1:8080"
        os.environ["WELLSCREEN_CLEANUP_PROJECT_ID"] = "production-project"
        self.assertEqual(self.post().status_code, 503)
        self.cleanup.assert_not_called()

    def test_emulator_demo_project_is_allowed(self):
        os.environ["FIRESTORE_EMULATOR_HOST"] = "127.0.0.1:8080"
        self.assertEqual(self.post().status_code, 200)
        self.cleanup.assert_called_once_with(
            dry_run=True, expected_project=PROJECT
        )

    def test_overlapping_run_is_rejected(self):
        self.assertTrue(route._cleanup_lock.acquire(blocking=False))
        try:
            self.assertEqual(self.post().status_code, 409)
            self.cleanup.assert_not_called()
        finally:
            route._cleanup_lock.release()

    def test_failure_is_sanitized_and_lock_is_released(self):
        self.cleanup.side_effect = RuntimeError("private database details")
        response = self.post()
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json(), {"detail": "Cleanup failed"})
        self.assertNotIn("private database details", response.text)
        self.cleanup.side_effect = None
        self.assertEqual(self.post().status_code, 200)

    def test_get_is_not_allowed(self):
        self.assertEqual(self.client.get(PATH, headers=self.headers).status_code, 405)
        self.cleanup.assert_not_called()


if __name__ == "__main__":
    unittest.main()
