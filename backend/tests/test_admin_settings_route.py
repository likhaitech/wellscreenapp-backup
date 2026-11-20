"""Route-level tests for GET/PATCH /admin/settings, run against the real
FastAPI app with TestClient. The 401 case is genuine end-to-end behavior;
authenticated cases override require_admin and patch the underlying
service functions since this sandbox has no Firebase credentials.
"""
from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.admin_auth_service import require_admin

client = TestClient(app)


def test_get_without_auth_header_is_rejected():
    response = client.get("/admin/settings/")
    assert response.status_code == 401


def test_get_returns_current_settings():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.get_system_settings",
            return_value={"minimum_app_version": "1.0.0"},
        ):
            response = client.get("/admin/settings/")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    body = response.json()
    assert body["minimum_app_version"] == "1.0.0"
    # The running server version (patch) is shown to the admin too.
    assert set(body["server"]) == {"version", "running_since"}


def test_get_service_error_becomes_500():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.get_system_settings",
            side_effect=RuntimeError("boom"),
        ):
            response = client.get("/admin/settings/")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 500


def test_patch_without_auth_header_is_rejected():
    response = client.patch("/admin/settings/", json={"maintenance_message": "Server maintenance tonight"})
    assert response.status_code == 401


def test_patch_applies_changes_and_writes_an_audit_log():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings",
            return_value={"maintenance_message": "Server maintenance tonight"},
        ) as mock_update, patch(
            "app.routes.admin_settings.create_system_log"
        ) as mock_log:
            response = client.patch(
                "/admin/settings/", json={"maintenance_message": "Server maintenance tonight"}
            )
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    assert response.json() == {"maintenance_message": "Server maintenance tonight"}
    mock_update.assert_called_once_with(
        {"maintenance_message": "Server maintenance tonight"}, updated_by="admin-1"
    )
    mock_log.assert_called_once()
    assert mock_log.call_args.kwargs["action"] == "system_settings_updated"
    assert mock_log.call_args.kwargs["actor_uid"] == "admin-1"


def test_patch_with_no_fields_sends_empty_changes():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings", return_value={}
        ) as mock_update, patch("app.routes.admin_settings.create_system_log"):
            response = client.patch("/admin/settings/", json={})
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    mock_update.assert_called_once_with({}, updated_by="admin-1")


def test_patch_service_error_becomes_500():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings",
            side_effect=RuntimeError("boom"),
        ):
            response = client.patch(
                "/admin/settings/", json={"maintenance_message": ""}
            )
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 500


def _as_admin():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}


def test_patch_endpoint_requires_auth():
    r = client.post("/admin/settings/patch", json={"settings": {"minimum_app_version": "1.1.0"}})
    assert r.status_code == 401


def test_system_patch_applies_valid_settings_and_logs():
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings", return_value={"minimum_app_version": "1.1.0"}) as upd, \
             patch("app.routes.admin_settings.create_system_log") as log:
            r = client.post(
                "/admin/settings/patch",
                json={"version": "1.0.1", "settings": {"minimum_app_version": "1.1.0", "maintenance_message": "Update needed"}},
            )
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r.status_code == 200
    assert r.json()["applied"] is True
    upd.assert_called_once()
    assert log.call_args.kwargs["action"] == "system_patch_applied"


def test_system_patch_rejects_unknown_key_and_changes_nothing():
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings") as upd, \
             patch("app.routes.admin_settings.create_system_log") as log:
            r = client.post("/admin/settings/patch", json={"settings": {"hack_enabled": True}})
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r.status_code == 422
    upd.assert_not_called()
    assert log.call_args.kwargs["action"] == "system_patch_rejected"


def test_system_patch_rejects_wrong_type_and_out_of_range():
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings") as upd, \
             patch("app.routes.admin_settings.create_system_log"):
            r1 = client.post("/admin/settings/patch", json={"settings": {"minimum_app_version": "one.four"}})
            r2 = client.post("/admin/settings/patch", json={"settings": {"minimum_app_version": "1.4"}})
            r3 = client.post("/admin/settings/patch", json={"settings": {}})
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r1.status_code == r2.status_code == r3.status_code == 422
    upd.assert_not_called()


def test_system_patch_validate_only_does_not_apply():
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings") as upd:
            r = client.post("/admin/settings/patch", json={"validate_only": True, "settings": {"minimum_app_version": "1.1.0"}})
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r.status_code == 200 and r.json()["applied"] is False
    upd.assert_not_called()


def test_system_patch_rejects_bad_version_long_notice_and_removed_settings():
    # The demo cases: a version that isn't x.y.z (number or text), a notice
    # over 200 characters, and a removed setting are refused with no change.
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings") as upd, \
             patch("app.routes.admin_settings.create_system_log"):
            r1 = client.post("/admin/settings/patch", json={"settings": {"minimum_app_version": 140}})
            r2 = client.post("/admin/settings/patch", json={"settings": {"maintenance_message": "x" * 201}})
            r3 = client.post("/admin/settings/patch", json={"settings": {"focus_mode_enabled": False}})
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r1.status_code == r2.status_code == r3.status_code == 422
    upd.assert_not_called()


def test_system_patch_applies_version_and_notice():
    _as_admin()
    try:
        with patch("app.routes.admin_settings.update_system_settings", return_value={}) as upd, \
             patch("app.routes.admin_settings.create_system_log"):
            r = client.post("/admin/settings/patch", json={
                "version": "1.4.0",
                "settings": {"minimum_app_version": "1.4.0", "maintenance_message": "Maintenance at 10 PM"},
            })
    finally:
        app.dependency_overrides.pop(require_admin, None)
    assert r.status_code == 200 and r.json()["applied"] is True
    assert upd.call_args.args[0] == {"minimum_app_version": "1.4.0", "maintenance_message": "Maintenance at 10 PM"}
