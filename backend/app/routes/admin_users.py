
import logging

from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth

from app.models.admin_user import (
    CreateUserRequest,
    UpdateUserRequest,
)
from app.services.admin_auth_service import require_admin
from app.services.system_log_service import create_system_log
from app.services.user_admin_service import (
    PairedRoleConflictError,
    create_user,
    delete_user,
    get_user,
    list_users,
    update_user,
)

router = APIRouter(
    prefix="/admin/users",
    tags=["Admin Users"],
)

logger = logging.getLogger(__name__)


def _safe_create_system_log(**kwargs) -> None:
    """
    Logging should not cause the actual admin operation to fail.
    """
    try:
        create_system_log(**kwargs)
    except Exception:
        logger.exception("Failed to create system log")


@router.get("/")
def get_users(
    current_admin: dict = Depends(require_admin),
):
    try:
        return {
            "users": list_users()
        }

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.get("/{uid}")
def get_user_by_uid(
    uid: str,
    current_admin: dict = Depends(require_admin),
):
    try:
        return get_user(uid)

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_new_user(
    request: CreateUserRequest,
    current_admin: dict = Depends(require_admin),
):
    if request.role not in {"parent", "child", "admin"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Role must be 'parent', 'child', or 'admin'",
        )

    try:
        created_user = create_user(
            email=request.email,
            password=request.password,
            display_name=request.display_name,
            role=request.role,
            disabled=request.disabled,
        )

        _safe_create_system_log(
            level="info",
            action="admin_user_created",
            message="Admin created a user account",
            actor_uid=current_admin.get("uid"),
            details={
                "target_uid": created_user.get("uid"),
                "email": str(request.email),
                "role": request.role,
                "disabled": request.disabled,
            },
        )

        return created_user

    except auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.patch("/{uid}")
def edit_user(
    uid: str,
    request: UpdateUserRequest,
    current_admin: dict = Depends(require_admin),
):
    current_admin_uid = current_admin.get("uid")

    if request.role is not None and request.role not in {
        "parent",
        "child",
        "admin",
    }:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Role must be 'parent', 'child', or 'admin'",
        )

    # Administrators must not disable or demote themselves.
    if uid == current_admin_uid:
        if request.disabled is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot disable your own admin account",
            )

        if request.role is not None and request.role != "admin":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot remove your own admin role",
            )

    try:
        updated_user = update_user(
            uid,
            email=request.email,
            password=request.password,
            display_name=request.display_name,
            role=request.role,
            disabled=request.disabled,
        )

        changes = request.model_dump(exclude_none=True)

        # Never store passwords in system logs.
        password_changed = "password" in changes
        changes.pop("password", None)

        if "email" in changes:
            changes["email"] = str(changes["email"])

        if password_changed:
            changes["password_changed"] = True

        _safe_create_system_log(
            level="info",
            action="admin_user_updated",
            message="Admin updated a user account",
            actor_uid=current_admin_uid,
            details={
                "target_uid": uid,
                "changes": changes,
            },
        )

        return updated_user

    except PairedRoleConflictError as exc:
        # A paired parent or child must be unpaired before
        # switching between parent and child account types.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        )

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.delete("/{uid}")
def remove_user(
    uid: str,
    current_admin: dict = Depends(require_admin),
):
    current_admin_uid = current_admin.get("uid")

    if uid == current_admin_uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot delete your own admin account",
        )

    try:
        target_user = get_user(uid)

        delete_user(uid)

        _safe_create_system_log(
            level="info",
            action="admin_user_deleted",
            message="Admin deleted a user account",
            actor_uid=current_admin_uid,
            details={
                "target_uid": uid,
                "email": target_user.get("email"),
                "role": target_user.get("role"),
            },
        )

        return {
            "message": "User deleted successfully"
        }

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
