from __future__ import annotations

from typing import Any

from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .firebase_service import get_firestore_client, initialize_firebase


def _serialize_user(user: auth.UserRecord) -> dict[str, Any]:
    return {
        "uid": user.uid,
        "email": user.email,
        "display_name": user.display_name,
        "disabled": user.disabled,
        "email_verified": user.email_verified,
        "role": (user.custom_claims or {}).get("role", "user"),
        "created_at": (
            user.user_metadata.creation_timestamp
            if user.user_metadata
            else None
        ),
        "last_sign_in_at": (
            user.user_metadata.last_sign_in_timestamp
            if user.user_metadata
            else None
        ),
    }


def list_users() -> list[dict[str, Any]]:
    initialize_firebase()

    users = auth.list_users()

    return [
        _serialize_user(user)
        for user in users.iterate_all()
    ]


def get_user(uid: str) -> dict[str, Any]:
    initialize_firebase()

    user = auth.get_user(uid)

    return _serialize_user(user)


def create_user(
    *,
    email: str,
    password: str,
    display_name: str | None = None,
    role: str = "user",
    disabled: bool = False,
) -> dict[str, Any]:

    initialize_firebase()

    user = auth.create_user(
        email=email,
        password=password,
        display_name=display_name,
        disabled=disabled,
    )

    try:
        claims = {
            "role": role,
            "admin": role == "admin",
        }

        auth.set_custom_user_claims(
            user.uid,
            claims,
        )

        db = get_firestore_client()

        db.collection("users").document(user.uid).set(
            {
                "uid": user.uid,
                "email": user.email,
                "fullName": display_name,
                "role": role,
                "disabled": disabled,
                "createdAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
    except Exception:
        # FIX: auth.create_user() above already created the Auth account.
        # If either write below it fails (a Firestore hiccup, a transient
        # network error), that account is left permanently orphaned - no
        # custom claims and/or no users/{uid} doc, but the email is
        # already taken. The admin sees a 500 and, on retry, a confusing
        # 409 "email already exists" (auth.EmailAlreadyExistsError, see
        # admin_users.py's create_new_user) with no way to complete the
        # create through this endpoint. Delete the orphaned Auth account
        # so a retry with the same email can succeed cleanly instead.
        try:
            auth.delete_user(user.uid)
        except Exception:
            pass  # best-effort cleanup - surface the original error either way
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

    initialize_firebase()

    update_data: dict[str, Any] = {}

    if email is not None:
        update_data["email"] = email

    if password is not None:
        update_data["password"] = password

    if display_name is not None:
        update_data["display_name"] = display_name

    if disabled is not None:
        update_data["disabled"] = disabled

    if update_data:
        auth.update_user(
            uid,
            **update_data,
        )

    current_user = auth.get_user(uid)
    current_claims = dict(
        current_user.custom_claims or {}
    )
    was_admin = bool(current_claims.get("admin"))

    if role is not None:
        current_claims["role"] = role
        current_claims["admin"] = role == "admin"

        auth.set_custom_user_claims(
            uid,
            current_claims,
        )

    demoted_from_admin = was_admin and role is not None and role != "admin"

    if disabled is True or demoted_from_admin:
        # FIX: Firebase ID tokens are verified statelessly by default (see
        # admin_auth_service.require_admin / user_auth_service.require_user),
        # so disabling an account here alone did NOT stop an already-issued
        # token (valid up to 1h) from continuing to pass auth.verify_id_token
        # on every admin/alert route. revoke_refresh_tokens() marks a
        # revocation timestamp Firebase checks when the caller verifies with
        # check_revoked=True (see the require_admin/require_user fix in
        # admin_auth_service.py / user_auth_service.py) - without both
        # halves of this fix, disabling a user is close to a no-op for up
        # to an hour, which defeats the point of an admin "disable" action
        # in a parental-control app. Same hole exists for demoting an admin
        # to a non-admin role: set_custom_user_claims() only affects
        # future tokens, so a just-demoted admin's still-valid token keeps
        # passing require_admin's "admin" claim check until it naturally
        # expires unless we revoke it here too.
        auth.revoke_refresh_tokens(uid)

    db = get_firestore_client()

    firestore_update: dict[str, Any] = {
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }

    if email is not None:
        firestore_update["email"] = email

    if display_name is not None:
        firestore_update["fullName"] = display_name

    if role is not None:
        firestore_update["role"] = role

    if disabled is not None:
        firestore_update["disabled"] = disabled

    db.collection("users").document(uid).set(
        firestore_update,
        merge=True,
    )

    return get_user(uid)


def _delete_family_data(db: Any, uid: str, role: str) -> dict[str, int]:
    """Remove the monitoring data tied to an account being deleted.

    Before this, deleting an account removed only the login and the
    users/{uid} document, leaving child profiles - with location, usage,
    browsing and chat history - behind with no owner.

    * guardian: every child profile they own is deleted (with all its
      subcollections), each paired child account is set back to
      not_paired, and the guardian's rules and pairing codes are removed.
    * child: the child profile linked to that account is deleted, since
      it holds that child's personal monitoring data.
    """
    deleted = {"child_profiles": 0, "unlinked_children": 0, "pairing_codes": 0}
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

    # FIX: revoke before delete, same reasoning as update_user's disabled
    # branch above - an already-issued ID token for this uid must stop
    # verifying immediately, not just once it happens to expire.
    auth.revoke_refresh_tokens(uid)

    db = get_firestore_client()
    user_ref = db.collection("users").document(uid)
    user_snapshot = user_ref.get()
    user_data = (user_snapshot.to_dict() or {}) if user_snapshot.exists else {}
    role = str(user_data.get("role") or "")

    # Family data goes first, while the login still exists: if this step
    # fails, the admin can simply retry the delete.
    _delete_family_data(db, uid, role)

    auth.delete_user(uid)

    user_ref.delete()
