"""Route-level tests for /admin/users (list, get, create, update, delete),
run against the real FastAPI app with TestClient. The 401 case is genuine
end-to-end behavior; authenticated cases override require_admin and patch
the underlying service functions since this sandbox has no Firebase
credentials.

The self-protection checks (an admin can't disable/demote/delete their own
account) are real route-level validation that runs before the service
layer is even called, so those are tested here rather than in
test_user_admin_service.py.
"""
from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient
from firebase_admin import auth

from app.main import app
from app.services.admin_auth_service import require_admin

client = TestClient(app)


def _as_admin(uid: str = "admin-1"):
    app.dependency_overrides[require_admin] = lambda: {"uid": uid, "admin": True}


def _clear_override():
    app.dependency_overrides.pop(require_admin, None)


# ---------------------------------------------------------------- GET /


def test_list_without_auth_header_is_rejected():
    response = client.get("/admin/users/")
    assert response.status_code == 401


def test_list_returns_wrapped_users():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.list_users",
            return_value=[{"uid": "u1"}, {"uid": "u2"}],
        ):
            response = client.get("/admin/users/")
    finally:
        _clear_override()

    assert response.status_code == 200
    assert response.json() == {"users": [{"uid": "u1"}, {"uid": "u2"}]}


# ------------------------------------------------------------ GET /{uid}


def test_get_by_uid_not_found_returns_404():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.get_user",
            side_effect=auth.UserNotFoundError("no such user"),
        ):
            response = client.get("/admin/users/ghost")
    finally:
        _clear_override()

    assert response.status_code == 404


def test_get_by_uid_success():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.get_user", return_value={"uid": "u1", "role": "user"}
        ):
            response = client.get("/admin/users/u1")
    finally:
        _clear_override()

    assert response.status_code == 200
    assert response.json() == {"uid": "u1", "role": "user"}


# --------------------------------------------------------------- POST /


def test_create_rejects_invalid_role_before_calling_service():
    _as_admin()
    try:
        with patch("app.routes.admin_users.create_user") as mock_create:
            response = client.post(
                "/admin/users/",
                json={
                    "email": "new@example.com",
                    "password": "secret123",
                    "role": "superuser",
                },
            )
    finally:
        _clear_override()

    assert response.status_code == 400
    mock_create.assert_not_called()


def test_create_success_logs_and_returns_created_user():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.create_user",
            return_value={"uid": "new-uid", "email": "new@example.com", "role": "user"},
        ), patch("app.routes.admin_users.create_system_log") as mock_log:
            response = client.post(
                "/admin/users/",
                json={
                    "email": "new@example.com",
                    "password": "secret123",
                    "role": "parent",
                },
            )
    finally:
        _clear_override()

    assert response.status_code == 201
    assert response.json()["uid"] == "new-uid"
    mock_log.assert_called_once()
    assert mock_log.call_args.kwargs["action"] == "admin_user_created"
    # The system log must never contain the plaintext password.
    assert "password" not in mock_log.call_args.kwargs["details"]


def test_create_duplicate_email_returns_409():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.create_user",
            side_effect=auth.EmailAlreadyExistsError("dup", cause=None, http_response=None),
        ):
            response = client.post(
                "/admin/users/",
                json={"email": "dup@example.com", "password": "secret123"},
            )
    finally:
        _clear_override()

    assert response.status_code == 409


# ------------------------------------------------------------ PATCH /{uid}


def test_edit_rejects_invalid_role():
    _as_admin()
    try:
        with patch("app.routes.admin_users.update_user") as mock_update:
            response = client.patch(
                "/admin/users/u2", json={"role": "superuser"}
            )
    finally:
        _clear_override()

    assert response.status_code == 400
    mock_update.assert_not_called()


def test_admin_cannot_disable_their_own_account():
    _as_admin(uid="admin-1")
    try:
        with patch("app.routes.admin_users.update_user") as mock_update:
            response = client.patch(
                "/admin/users/admin-1", json={"disabled": True}
            )
    finally:
        _clear_override()

    assert response.status_code == 400
    mock_update.assert_not_called()


def test_admin_cannot_remove_their_own_admin_role():
    _as_admin(uid="admin-1")
    try:
        with patch("app.routes.admin_users.update_user") as mock_update:
            response = client.patch(
                "/admin/users/admin-1", json={"role": "user"}
            )
    finally:
        _clear_override()

    assert response.status_code == 400
    mock_update.assert_not_called()


def test_admin_can_still_edit_their_own_display_name():
    # Only self-disable and self-demote are blocked - other self-edits
    # (like renaming) must still go through.
    _as_admin(uid="admin-1")
    try:
        with patch(
            "app.routes.admin_users.update_user",
            return_value={"uid": "admin-1", "display_name": "New Name"},
        ), patch("app.routes.admin_users.create_system_log"):
            response = client.patch(
                "/admin/users/admin-1", json={"display_name": "New Name"}
            )
    finally:
        _clear_override()

    assert response.status_code == 200


def test_edit_not_found_returns_404():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.update_user",
            side_effect=auth.UserNotFoundError("no such user"),
        ):
            response = client.patch("/admin/users/ghost", json={"display_name": "x"})
    finally:
        _clear_override()

    assert response.status_code == 404


def test_edit_duplicate_email_returns_409():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.update_user",
            side_effect=auth.EmailAlreadyExistsError("dup", cause=None, http_response=None),
        ):
            response = client.patch(
                "/admin/users/u2", json={"email": "taken@example.com"}
            )
    finally:
        _clear_override()

    assert response.status_code == 409


def test_edit_password_change_is_logged_as_a_flag_not_the_password():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.update_user",
            return_value={"uid": "u2"},
        ), patch("app.routes.admin_users.create_system_log") as mock_log:
            response = client.patch(
                "/admin/users/u2", json={"password": "brand-new-secret"}
            )
    finally:
        _clear_override()

    assert response.status_code == 200
    details = mock_log.call_args.kwargs["details"]
    assert "password" not in details["changes"]
    assert details["changes"]["password_changed"] is True


# ----------------------------------------------------------- DELETE /{uid}


def test_admin_cannot_delete_their_own_account():
    _as_admin(uid="admin-1")
    try:
        with patch("app.routes.admin_users.delete_user") as mock_delete:
            response = client.delete("/admin/users/admin-1")
    finally:
        _clear_override()

    assert response.status_code == 400
    mock_delete.assert_not_called()


def test_delete_not_found_returns_404():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.get_user",
            side_effect=auth.UserNotFoundError("no such user"),
        ), patch("app.routes.admin_users.delete_user") as mock_delete:
            response = client.delete("/admin/users/ghost")
    finally:
        _clear_override()

    assert response.status_code == 404
    mock_delete.assert_not_called()


def test_delete_success_logs_target_details():
    _as_admin()
    try:
        with patch(
            "app.routes.admin_users.get_user",
            return_value={"uid": "u2", "email": "u2@example.com", "role": "user"},
        ), patch("app.routes.admin_users.delete_user") as mock_delete, patch(
            "app.routes.admin_users.create_system_log"
        ) as mock_log:
            response = client.delete("/admin/users/u2")
    finally:
        _clear_override()

    assert response.status_code == 200
    mock_delete.assert_called_once_with("u2")
    assert mock_log.call_args.kwargs["details"]["email"] == "u2@example.com"
