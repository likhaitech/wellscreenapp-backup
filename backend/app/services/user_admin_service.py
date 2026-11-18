from __future__ import annotations

from typing import Any

from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .firebase_service import get_firestore_client, initialize_firebase


VALID_ROLES = frozenset({"parent", "child", "admin"})
FAMILY_ROLES = frozenset({"parent", "child"})


class PairedRoleConflictError(ValueError):
    """A paired account cannot switch directly between parent and child."""


def _serialize_user(user: auth.UserRecord) -> dict[str, Any]:
    return {
        "uid": user.uid,
        "email": user.email,
        "display_name": user.display_name,
        "disabled": user.disabled,
        "email_verified": user.email_verified,
        "role": (user.custom_claims or {}).get("role", "parent"),
        "created_at": (
            user.user_metadata.creation_timestamp if user.user_metadata else None
        ),
        "last_sign_in_at": (
            user.user_metadata.last_sign_in_timestamp if user.user_metadata else None
        ),
    }


def list_users() -> list[dict[str, Any]]:
    initialize_firebase()
    return [_serialize_user(user) for user in auth.list_users().iterate_all()]


def get_user(uid: str) -> dict[str, Any]:
    initialize_firebase()
    return _serialize_user(auth.get_user(uid))


def create_user(
    *,
    email: str,
    password: str,
    display_name: str | None = None,
    role: str = "parent",
    disabled: bool = False,
) -> dict[str, Any]:
    if role not in VALID_ROLES:
        raise ValueError("Role must be 'parent', 'child', or 'admin'")

    initialize_firebase()
    user = auth.create_user(
        email=email,
        password=password,
        display_name=display_name,
        disabled=disabled,
    )

    try:
        auth.set_custom_user_claims(
            user.uid,
            {"role": role, "admin": role == "admin"},
        )

        user_data: dict[str, Any] = {
            "uid": user.uid,
            "email": user.email,
            "fullName": display_name,
            "role": role,
            "disabled": disabled,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        if role == "parent":
            user_data["childrenCount"] = 0
        elif role == "child":
            user_data.update(
                {
                    "pairingStatus": "not_paired",
                    "pairedParentId": None,
                    "pairedChildProfileId": None,
                }
            )
        else:
            # Directly created admins have no prior family role.
            user_data["previousRole"] = "parent"

        get_firestore_client().collection("users").document(user.uid).set(
            user_data, merge=True
        )
    except Exception:
        # Auth user creation succeeded, but claims or Firestore failed.
        # Best-effort cleanup avoids leaving an orphaned login/email.
        try:
            auth.delete_user(user.uid)
        except Exception:
            pass
        raise

    return get_user(user.uid)


def update_user(
    uid: str,
    *,
    email: str | None = None,
    password: str | None = None,
    display_name: str | None = None,
    role: str | None = None,
    disabled: bool | None = None,
) -> dict[str, Any]:
    if role is not None and role not in VALID_ROLES:
        raise ValueError("Role must be 'parent', 'child', or 'admin'")

    initialize_firebase()

    # Read and validate role/pairing state BEFORE any Auth mutation.
    current_user = auth.get_user(uid)
    original_claims = dict(current_user.custom_claims or {})
    db = get_firestore_client()
    user_ref = db.collection("users").document(uid)
    firestore_update: dict[str, Any] = {
        "updatedAt": firestore.SERVER_TIMESTAMP
    }

    current_role: str | None = None
    effective_role: str | None = None

    if role is not None:
        snapshot = user_ref.get()
        raw_data = snapshot.to_dict() if snapshot.exists else None
        account_data = raw_data if isinstance(raw_data, dict) else {}

        stored_role = account_data.get("role")
        claimed_role = original_claims.get("role")

        # An admin claim must never be mistaken for a regular account merely
        # because Firestore has an out-of-date role value.
        if (
            original_claims.get("admin") is True
            or claimed_role == "admin"
            or stored_role == "admin"
        ):
            current_role = "admin"
        elif stored_role in FAMILY_ROLES:
            current_role = stored_role
        elif claimed_role in FAMILY_ROLES:
            current_role = claimed_role
        else:
            current_role = "parent"  # Legacy accounts lacking a valid role.

        effective_role = role

        if current_role == "admin" and role != "admin":
            # The supplied non-admin role triggers demotion, but the account
            # always returns to its recorded pre-admin family role.
            previous_role = account_data.get("previousRole")
            effective_role = (
                previous_role if previous_role in FAMILY_ROLES else "parent"
            )

        elif current_role in FAMILY_ROLES and role == "admin":
            firestore_update["previousRole"] = current_role

        elif (
            current_role in FAMILY_ROLES
            and effective_role in FAMILY_ROLES
            and current_role != effective_role
        ):
            # A parent/child type change is only safe after unpairing.
            if current_role == "child":
                parent_id = account_data.get("pairedParentId")
                profile_id = account_data.get("pairedChildProfileId")
                paired = (
                    account_data.get("pairingStatus") == "connected"
                    or (isinstance(parent_id, str) and bool(parent_id.strip()))
                    or (isinstance(profile_id, str) and bool(profile_id.strip()))
                )
            else:
                # Profiles can be linked even when pairingStatus is absent.
                # Check the actual childAccountId, not just status or counts.
                query = db.collection("child_profiles").where(
                    filter=FieldFilter("parentId", "==", uid)
                )
                paired = False
                for profile in query.stream():
                    profile_data = profile.to_dict() or {}
                    child_uid = profile_data.get("childAccountId")
                    if (
                        profile_data.get("pairingStatus") == "connected"
                        or (
                            isinstance(child_uid, str)
                            and bool(child_uid.strip())
                        )
                    ):
                        paired = True
                        break

            if paired:
                raise PairedRoleConflictError(
                    "Cannot switch between parent and child while paired. "
                    "Unpair the account first."
                )

        # Update Firestore's role even when its existing role has drifted.
        firestore_update["role"] = effective_role

        if effective_role != current_role:
            if effective_role == "child" and current_role != "admin":
                # A direct, unpaired parent -> child transition.
                # Admin -> previous child must preserve existing pairing.
                firestore_update.update(
                    {
                        "pairingStatus": "not_paired",
                        "pairedParentId": None,
                        "pairedChildProfileId": None,
                    }
                )
            elif effective_role == "parent":
                # Preserve existing counts on admin -> previous parent.
                # Initialize a count when a directly created admin demotes.
                if not isinstance(account_data.get("childrenCount"), int):
                    firestore_update["childrenCount"] = 0

    update_data: dict[str, Any] = {}
    if email is not None:
        update_data["email"] = email
        firestore_update["email"] = email
    if password is not None:
        update_data["password"] = password
    if display_name is not None:
        update_data["display_name"] = display_name
        firestore_update["fullName"] = display_name
    if disabled is not None:
        update_data["disabled"] = disabled
        firestore_update["disabled"] = disabled

    if update_data:
        auth.update_user(uid, **update_data)

    claims_changed = False
    if effective_role is not None:
        updated_claims = dict(original_claims)
        updated_claims["role"] = effective_role
        updated_claims["admin"] = effective_role == "admin"
        claims_changed = updated_claims != original_claims
        if claims_changed:
            auth.set_custom_user_claims(uid, updated_claims)

    try:
        user_ref.set(firestore_update, merge=True)
    except Exception:
        # Firebase Auth and Firestore cannot share an atomic transaction.
        # Undo custom claims where possible; profile edits may still persist.
        if claims_changed:
            try:
                auth.set_custom_user_claims(uid, original_claims)
            except Exception:
                pass
        raise

    was_admin = (
        current_role == "admin" or original_claims.get("admin") is True
    )
    demoted_from_admin = (
        was_admin and effective_role is not None and effective_role != "admin"
    )

    if disabled is True or demoted_from_admin:
        # Backend authentication must use verify_id_token(check_revoked=True).
        auth.revoke_refresh_tokens(uid)

    return get_user(uid)


def _delete_family_data(db: Any, uid: str, role: str) -> dict[str, int]:
    """Remove owned monitoring data and unlink children before Auth deletion."""
    deleted = {
        "child_profiles": 0,
        "unlinked_children": 0,
        "pairing_codes": 0,
    }
    profiles = db.collection("child_profiles")

    if role == "parent":
        owned = profiles.where(filter=FieldFilter("parentId", "==", uid))
        for snapshot in owned.stream():
            data = snapshot.to_dict() or {}
            child_uid = data.get("childAccountId")
            if isinstance(child_uid, str) and child_uid:
                db.collection("users").document(child_uid).set(
                    {
                        "pairingStatus": "not_paired",
                        "pairedParentId": firestore.DELETE_FIELD,
                        "pairedChildProfileId": firestore.DELETE_FIELD,
                        "pairingCode": firestore.DELETE_FIELD,
                        "pairedAt": firestore.DELETE_FIELD,
                    },
                    merge=True,
                )
                deleted["unlinked_children"] += 1
            db.recursive_delete(snapshot.reference)
            deleted["child_profiles"] += 1

        db.collection("app_rules").document(uid).delete()
        codes = db.collection("pairing_codes").where(
            filter=FieldFilter("parentId", "==", uid)
        )
        for snapshot in codes.stream():
            snapshot.reference.delete()
            deleted["pairing_codes"] += 1

    elif role == "child":
        linked = profiles.where(filter=FieldFilter("childAccountId", "==", uid))
        for snapshot in linked.stream():
            db.recursive_delete(snapshot.reference)
            deleted["child_profiles"] += 1

    return deleted


def delete_user(uid: str) -> None:
    initialize_firebase()

    # Stop existing sessions before deleting the account.
    auth.revoke_refresh_tokens(uid)

    db = get_firestore_client()
    user_ref = db.collection("users").document(uid)
    user_snapshot = user_ref.get()
    user_data_raw = user_snapshot.to_dict() if user_snapshot.exists else None
    user_data = user_data_raw if isinstance(user_data_raw, dict) else {}

    role = user_data.get("role")
    if role == "admin":
        # An admin promoted from a family role may still own paired data.
        role = user_data.get("previousRole", "parent")

    # Complete family cleanup before deleting Auth, so failures are retryable.
    _delete_family_data(db, uid, role if role in FAMILY_ROLES else "")
    auth.delete_user(uid)
    user_ref.delete()
