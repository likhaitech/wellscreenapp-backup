"""Route-level tests for POST /alerts/notify and GET /health, run against
the real FastAPI app (app/main.py) with TestClient - this is what an IT
expert evaluator's "Alert Delivery Success Rate" and "System Response Time"
checklist items are actually probing at the API layer.

No live Firebase project is touched: the 401 case is genuine end-to-end
behavior (FastAPI's HTTPBearer dependency, no mocking needed). The
authenticated cases override the `require_user` dependency and patch
send_alert_notification, since this sandbox has no Firebase credentials.

Run with: pytest backend/tests/test_alerts_route.py -v
"""
from __future__ import annotations

import time
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.user_auth_service import require_user
from app.services.notification_service import NoDeviceTokenError, NotAuthorizedError

client = TestClient(app)


def test_health_endpoint_responds_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_endpoint_response_time_is_reasonable():
    # Local/in-process call - this is a sanity bound on the route handler
    # itself, not network latency (see the live-deployment timing in the
    # technical evaluation notes for that).
    start = time.perf_counter()
    response = client.get("/health")
    elapsed_ms = (time.perf_counter() - start) * 1000

    assert response.status_code == 200
    assert elapsed_ms < 500, f"in-process /health took {elapsed_ms:.1f}ms"


def test_notify_without_auth_header_is_rejected():
    response = client.post(
        "/alerts/notify",
        json={
            "parent_uid": "parent-1",
            "title": "t",
            "body": "b",
            "alert_type": "usage_limit",
        },
    )
    assert response.status_code == 401


def test_notify_success_path_returns_sent_status():
    app.dependency_overrides[require_user] = lambda: {"uid": "parent-1"}
    try:
        with patch(
            "app.routes.alerts.send_alert_notification",
            return_value={"status": "sent", "message_id": "abc123", "error": None},
        ):
            response = client.post(
                "/alerts/notify",
                json={
                    "parent_uid": "parent-1",
                    "title": "Usage limit reached",
                    "body": "body text",
                    "alert_type": "usage_limit",
                },
                headers={"Authorization": "Bearer fake-token-for-test"},
            )
    finally:
        app.dependency_overrides.pop(require_user, None)

    assert response.status_code == 200
    assert response.json() == {
        "status": "sent",
        "message_id": "abc123",
        "error": None,
    }


def test_notify_unauthorized_caller_returns_403():
    app.dependency_overrides[require_user] = lambda: {"uid": "stranger"}
    try:
        with patch(
            "app.routes.alerts.send_alert_notification",
            side_effect=NotAuthorizedError("not paired"),
        ):
            response = client.post(
                "/alerts/notify",
                json={
                    "parent_uid": "parent-1",
                    "title": "t",
                    "body": "b",
                    "alert_type": "usage_limit",
                },
                headers={"Authorization": "Bearer fake-token-for-test"},
            )
    finally:
        app.dependency_overrides.pop(require_user, None)

    assert response.status_code == 403


def test_notify_unexpected_error_returns_generic_500_not_internal_details():
    # FIX: unlike the admin/* routes (require_admin-gated - an already-
    # trusted admin seeing their own action's raw error is low-stakes),
    # this route is require_user-gated, so ANY signed-in parent or child
    # can trigger an unhandled exception here (e.g. a Firestore hiccup
    # inside caller_may_notify()/send_alert_notification() that isn't one
    # of the two typed exceptions covered above). The response must never
    # leak the real exception text to that caller.
    app.dependency_overrides[require_user] = lambda: {"uid": "parent-1"}
    try:
        with patch(
            "app.routes.alerts.send_alert_notification",
            side_effect=RuntimeError(
                "internal detail: firestore project wellscreen-prod-4471 unreachable"
            ),
        ):
            response = client.post(
                "/alerts/notify",
                json={
                    "parent_uid": "parent-1",
                    "title": "t",
                    "body": "b",
                    "alert_type": "usage_limit",
                },
                headers={"Authorization": "Bearer fake-token-for-test"},
            )
    finally:
        app.dependency_overrides.pop(require_user, None)

    assert response.status_code == 500
    detail = response.json()["detail"]
    assert detail == "Failed to send alert notification."
    assert "firestore" not in detail.lower()
    assert "wellscreen-prod-4471" not in detail


def test_notify_missing_device_token_returns_200_with_failed_status():
    # Documented as "not a server error" in alerts.py - the recipient just
    # hasn't registered a device yet, so this must be 200 + failed status,
    # not a 4xx/5xx, so the caller can distinguish it from a real error.
    app.dependency_overrides[require_user] = lambda: {"uid": "parent-1"}
    try:
        with patch(
            "app.routes.alerts.send_alert_notification",
            side_effect=NoDeviceTokenError("no token on file"),
        ):
            response = client.post(
                "/alerts/notify",
                json={
                    "parent_uid": "parent-1",
                    "title": "t",
                    "body": "b",
                    "alert_type": "usage_limit",
                },
                headers={"Authorization": "Bearer fake-token-for-test"},
            )
    finally:
        app.dependency_overrides.pop(require_user, None)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "failed"
    assert "no token on file" in body["error"]


# Task 11b: Device Admin deactivation alert
def test_device_admin_disabled_alert_forwards_to_notification_service():
    app.dependency_overrides[require_user] = lambda: {
        "uid": "child-1"
    }

    try:
        with patch(
            "app.routes.alerts.send_alert_notification",
            return_value={
                "status": "sent",
                "message_id": "device-admin-alert-1",
                "error": None,
            },
        ) as mock_send:
            response = client.post(
                "/alerts/notify",
                json={
                    "parent_uid": "parent-1",
                    "title": "WellScreen uninstall protection disabled",
                    "body": (
                        "Device Admin protection has been disabled "
                        "on your child's device."
                    ),
                    "alert_type": "device_admin_disabled",
                    "data": {
                        "childProfileId": "profile-1",
                        "timestampMs": 1760000000000,
                    },
                },
                headers={
                    "Authorization": "Bearer fake-token-for-test"
                },
            )

            mock_send.assert_called_once_with(
                caller_uid="child-1",
                parent_uid="parent-1",
                title="WellScreen uninstall protection disabled",
                body=(
                    "Device Admin protection has been disabled "
                    "on your child's device."
                ),
                data={
                    "alertType": "device_admin_disabled",
                    "childProfileId": "profile-1",
                    "timestampMs": 1760000000000,
                },
            )
    finally:
        app.dependency_overrides.pop(require_user, None)

    assert response.status_code == 200
    assert response.json()["status"] == "sent"
    assert response.json()["message_id"] == "device-admin-alert-1"