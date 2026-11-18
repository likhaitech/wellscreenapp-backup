"""Tests for app/services/user_admin_service.py - backs all of
/admin/users. The behaviors worth pinning down here aren't the CRUD
plumbing itself but the two security-relevant FIXes documented inline in
the source: disabling a user or deleting a user must call
auth.revoke_refresh_tokens() so an already-issued token stops working
immediately (see admin_auth_service/user_auth_service's check_revoked=True,
tested separately) - without this, "disable" is close to a no-op for up to
an hour. Also covers create_user's custom-claims + Firestore write, and
that update_user only touches the fields it was actually given.

firebase_admin.auth and the Firestore client are both mocked - no real
Firebase project is touched.
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.services import user_admin_service as svc


def _fake_user_record(
    uid="u1",
    email="user@example.com",
    display_name="Some User",
    disabled=False,
    email_verified=True,
    custom_claims=None,
):
    record = MagicMock()
    record.uid = uid
    record.email = email
    record.display_name = display_name
    record.disabled = disabled
    record.email_verified = email_verified
    record.custom_claims = custom_claims
    record.user_metadata.creation_timestamp = 1000
    record.user_metadata.last_sign_in_timestamp = 2000
    return record


class TestListUsers:
    def test_serializes_every_user_from_iterate_all(self):
        page = MagicMock()
        page.iterate_all.return_value = [
            _fake_user_record(uid="u1"),
            _fake_user_record(uid="u2", custom_claims={"role": "admin", "admin": True}),
        ]

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "list_users", return_value=page
        ):
            result = svc.list_users()

        assert [u["uid"] for u in result] == ["u1", "u2"]
        assert result[0]["role"] == "parent"  # no custom_claims -> defaults to "parent"
        assert result[1]["role"] == "admin"


class TestGetUser:
    def test_serializes_role_from_custom_claims(self):
        record = _fake_user_record(custom_claims={"role": "admin"})

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ):
            result = svc.get_user("u1")

        assert result["uid"] == "u1"
        assert result["role"] == "admin"
        assert result["created_at"] == 1000
        assert result["last_sign_in_at"] == 2000


class TestCreateUser:
    def test_sets_custom_claims_matching_requested_role(self):
        created = _fake_user_record(uid="new-uid")
        fetched = _fake_user_record(uid="new-uid", custom_claims={"role": "admin", "admin": True})
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims") as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(
            svc.auth, "get_user", return_value=fetched
        ):
            result = svc.create_user(
                email="new@example.com",
                password="secret123",
                display_name="New User",
                role="admin",
            )

        mock_claims.assert_called_once_with("new-uid", {"role": "admin", "admin": True})
        assert result["role"] == "admin"

    def test_default_role_is_parent_with_admin_false(self):
        created = _fake_user_record(uid="new-uid")
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims") as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(email="new@example.com", password="secret123")

        mock_claims.assert_called_once_with("new-uid", {"role": "parent", "admin": False})

    def test_firestore_write_failure_deletes_the_orphaned_auth_account(self):
        # FIX: auth.create_user() already created the Auth account before
        # this Firestore write runs. Without cleanup, a failure here left
        # that account permanently orphaned - no Firestore doc, but the
        # email already taken (a retry would 409 "email already exists").
        created = _fake_user_record(uid="new-uid", email="new@example.com")
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.set.side_effect = (
            RuntimeError("firestore unavailable")
        )

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "delete_user") as mock_delete:
            try:
                svc.create_user(email="new@example.com", password="secret123")
                raised = False
            except RuntimeError:
                raised = True

        assert raised, "the original error must still propagate"
        mock_delete.assert_called_once_with("new-uid")

    def test_custom_claims_failure_also_deletes_the_orphaned_auth_account(self):
        created = _fake_user_record(uid="new-uid", email="new@example.com")

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(
            svc.auth,
            "set_custom_user_claims",
            side_effect=RuntimeError("claims service unavailable"),
        ), patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ), patch.object(svc.auth, "delete_user") as mock_delete:
            try:
                svc.create_user(email="new@example.com", password="secret123")
            except RuntimeError:
                pass

        mock_delete.assert_called_once_with("new-uid")

    def test_writes_a_users_firestore_document(self):
        created = _fake_user_record(uid="new-uid", email="new@example.com")
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(
                email="new@example.com", password="secret123", role="parent", disabled=False
            )

        fake_db.collection.assert_called_once_with("users")
        fake_db.collection.return_value.document.assert_called_once_with("new-uid")
        written = fake_db.collection.return_value.document.return_value.set.call_args[0][0]
        assert written["uid"] == "new-uid"
        assert written["email"] == "new@example.com"
        assert written["role"] == "parent"
        assert written["childrenCount"] == 0

    def test_child_account_starts_unpaired(self):
        created = _fake_user_record(uid="child-uid")
        fake_db = MagicMock()
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims") as claims, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(email="child@example.com", password="secret123", role="child")

        claims.assert_called_once_with("child-uid", {"role": "child", "admin": False})
        written = fake_db.collection.return_value.document.return_value.set.call_args.args[0]
        assert written["role"] == "child"
        assert written["pairingStatus"] == "not_paired"
        assert written["pairedParentId"] is None
        assert written["pairedChildProfileId"] is None

    def test_admin_account_has_default_previous_role(self):
        created = _fake_user_record(uid="admin-uid")
        fake_db = MagicMock()
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(email="admin@example.com", password="secret123", role="admin")

        written = fake_db.collection.return_value.document.return_value.set.call_args.args[0]
        assert written["role"] == "admin"
        assert written["previousRole"] == "parent"

    def test_rejects_legacy_user_role_before_auth_creation(self):
        with patch.object(svc, "initialize_firebase") as initialize, patch.object(
            svc.auth, "create_user"
        ) as auth_create:
            with pytest.raises(ValueError, match="Role must be"):
                svc.create_user(email="wrong@example.com", password="secret123", role="user")
        initialize.assert_not_called()
        auth_create.assert_not_called()


class TestUpdateUser:
    def test_only_provided_fields_are_sent_to_auth_update_user(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ) as mock_update, patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=MagicMock()):
            svc.update_user("u1", display_name="Renamed")

        mock_update.assert_called_once_with("u1", display_name="Renamed")

    def test_no_changes_at_all_does_not_call_auth_update_user(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ) as mock_update, patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=MagicMock()):
            svc.update_user("u1")

        mock_update.assert_not_called()

    def test_role_change_preserves_other_existing_custom_claims(self):
        current = _fake_user_record(custom_claims={"role": "parent", "admin": False, "extra": "keep-me"})

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=current
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ) as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="admin")

        mock_claims.assert_called_once_with(
            "u1", {"role": "admin", "admin": True, "extra": "keep-me"}
        )

    def test_disabling_a_user_revokes_refresh_tokens(self):
        # This is the security-relevant FIX documented in the source:
        # disabling alone doesn't stop an already-issued token for up to an
        # hour, so revoke_refresh_tokens must be called too.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record(disabled=True)
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", disabled=True)

        mock_revoke.assert_called_once_with("u1")

    def test_enabling_or_leaving_disabled_untouched_does_not_revoke(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record(disabled=False)
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", disabled=False)
            svc.update_user("u1", display_name="No disabled arg at all")

        mock_revoke.assert_not_called()

    def test_demoting_an_admin_revokes_refresh_tokens(self):
        # Same class of bug as the disabled-path FIX above, for the role
        # path: set_custom_user_claims() only affects tokens issued AFTER
        # the change - a just-demoted admin's already-issued token keeps
        # carrying "admin": true and keeps passing require_admin's claim
        # check (see admin_auth_service.py) until it expires (up to 1h)
        # unless the demotion also revokes it here.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "admin", "admin": True}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="parent")

        mock_revoke.assert_called_once_with("u1")

    def test_promoting_to_admin_does_not_revoke(self):
        # The hole only exists in one direction (an admin's already-issued
        # token outliving its claims) - a newly-promoted admin's OLD token
        # correctly still lacks the admin claim, so there's nothing stale
        # to revoke on promotion.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "parent", "admin": False}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="admin")

        mock_revoke.assert_not_called()

    def test_non_admin_role_change_does_not_revoke(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "parent", "admin": False}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="child")

        mock_revoke.assert_not_called()

    def test_firestore_update_only_contains_provided_fields(self):
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.update_user("u1", display_name="Renamed Only")

        written = fake_db.collection.return_value.document.return_value.set.call_args[0][0]
        assert written["fullName"] == "Renamed Only"
        assert "email" not in written
        assert "role" not in written
        assert "disabled" not in written
        assert "updatedAt" in written


class _Snap:
    def __init__(self, ref, data, exists=True):
        self.reference = ref
        self._data = data
        self.exists = exists

    def to_dict(self):
        return dict(self._data)


class _FakeDb:
    """Minimal Firestore double recording what delete_user touches."""

    def __init__(self, users=None, profiles=None, codes=None):
        self.users = users or {}
        self.profiles = profiles or {}
        self.codes = codes or {}
        self.recursive_deleted = []
        self.deleted_docs = []
        self.user_sets = {}

    def recursive_delete(self, ref):
        self.recursive_deleted.append(ref.path)

    def collection(self, name):
        db = self

        class _Doc:
            def __init__(self, doc_id):
                self.path = f"{name}/{doc_id}"
                self.doc_id = doc_id

            def get(self):
                data = db.users.get(self.doc_id)
                return _Snap(self, data or {}, exists=data is not None)

            def set(self, data, merge=False):
                db.user_sets[self.path] = data

            def delete(self):
                db.deleted_docs.append(self.path)

        class _Query:
            def __init__(self, rows):
                self.rows = rows

            def stream(self):
                return iter(self.rows)

        class _Col:
            def document(self, doc_id):
                return _Doc(doc_id)

            def where(self, *, filter):
                field, value = filter.field_path, filter.value
                source = {"child_profiles": db.profiles, "pairing_codes": db.codes}[name]
                return _Query(
                    [
                        _Snap(_Doc(doc_id), data)
                        for doc_id, data in source.items()
                        if data.get(field) == value
                    ]
                )

        return _Col()



class TestRoleManagement:
    """New F10 role rules. Firebase Auth and Firestore remain mocked."""

    def test_promoting_child_to_admin_preserves_previous_role(self):
        db = _FakeDb(users={"u1": {"role": "child", "pairingStatus": "not_paired"}})
        record = _fake_user_record(custom_claims={"role": "child", "admin": False})
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ), patch.object(svc.auth, "set_custom_user_claims") as set_claims, patch.object(
            svc, "get_firestore_client", return_value=db
        ):
            svc.update_user("u1", role="admin")

        assert db.user_sets["users/u1"]["role"] == "admin"
        assert db.user_sets["users/u1"]["previousRole"] == "child"
        set_claims.assert_called_once_with("u1", {"role": "admin", "admin": True})

    def test_admin_demotion_restores_previous_child_role_and_revokes(self):
        db = _FakeDb(users={"u1": {"role": "admin", "previousRole": "child"}})
        record = _fake_user_record(custom_claims={"role": "admin", "admin": True})
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ), patch.object(svc.auth, "set_custom_user_claims") as set_claims, patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as revoke, patch.object(svc, "get_firestore_client", return_value=db):
            svc.update_user("u1", role="parent")

        assert db.user_sets["users/u1"]["role"] == "child"
        set_claims.assert_called_once_with("u1", {"role": "child", "admin": False})
        revoke.assert_called_once_with("u1")

    def test_paired_child_cannot_become_parent_or_change_password(self):
        db = _FakeDb(users={"u1": {
            "role": "child", "pairingStatus": "connected",
            "pairedParentId": "p1", "pairedChildProfileId": "profile1",
        }})
        record = _fake_user_record(custom_claims={"role": "child", "admin": False})
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ), patch.object(svc.auth, "update_user") as auth_update, patch.object(
            svc.auth, "set_custom_user_claims"
        ) as set_claims, patch.object(svc, "get_firestore_client", return_value=db):
            with pytest.raises(svc.PairedRoleConflictError):
                svc.update_user("u1", role="parent", password="new-secret123")

        auth_update.assert_not_called()
        set_claims.assert_not_called()
        assert "users/u1" not in db.user_sets

    def test_paired_parent_cannot_become_child_when_profile_is_linked(self):
        # Paired child_profiles may carry parentId and childAccountId without
        # a pairingStatus field. This must still count as an active pairing.
        db = _FakeDb(
            users={"p1": {"role": "parent", "childrenCount": 1}},
            profiles={"profile1": {"parentId": "p1", "childAccountId": "c1"}},
        )
        record = _fake_user_record(uid="p1", custom_claims={"role": "parent", "admin": False})
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ), patch.object(svc.auth, "update_user") as auth_update, patch.object(
            svc.auth, "set_custom_user_claims"
        ) as set_claims, patch.object(svc, "get_firestore_client", return_value=db):
            with pytest.raises(svc.PairedRoleConflictError):
                svc.update_user("p1", role="child")

        auth_update.assert_not_called()
        set_claims.assert_not_called()
        assert "users/p1" not in db.user_sets

    def test_unpaired_parent_can_become_child(self):
        db = _FakeDb(users={"p1": {"role": "parent", "childrenCount": 0}})
        record = _fake_user_record(uid="p1", custom_claims={"role": "parent", "admin": False})
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ), patch.object(svc.auth, "set_custom_user_claims") as set_claims, patch.object(
            svc, "get_firestore_client", return_value=db
        ):
            svc.update_user("p1", role="child")

        written = db.user_sets["users/p1"]
        assert written["role"] == "child"
        assert written["pairingStatus"] == "not_paired"
        assert written["pairedParentId"] is None
        assert written["pairedChildProfileId"] is None
        set_claims.assert_called_once_with("p1", {"role": "child", "admin": False})


def _run_delete(fake_db, uid):
    with patch.object(svc, "initialize_firebase"), patch.object(
        svc.auth, "revoke_refresh_tokens"
    ), patch.object(svc.auth, "delete_user") as auth_delete, patch.object(
        svc, "get_firestore_client", return_value=fake_db
    ):
        svc.delete_user(uid)
    return auth_delete


class TestDeleteUser:
    def test_revokes_tokens_before_deleting_the_auth_account(self):
        fake_db = MagicMock()
        call_order = []

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "revoke_refresh_tokens",
            side_effect=lambda uid: call_order.append("revoke"),
        ), patch.object(
            svc.auth,
            "delete_user",
            side_effect=lambda uid: call_order.append("delete"),
        ), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ):
            svc.delete_user("u1")

        assert call_order == ["revoke", "delete"]

    def test_also_deletes_the_users_firestore_document(self):
        fake_db = _FakeDb(users={"u1": {"role": "parent"}})
        _run_delete(fake_db, "u1")
        assert "users/u1" in fake_db.deleted_docs

    def test_guardian_delete_removes_their_child_profiles_and_rules(self):
        fake_db = _FakeDb(
            users={"p1": {"role": "parent"}, "c1": {"role": "child"}},
            profiles={
                "prof1": {"parentId": "p1", "childAccountId": "c1"},
                "prof2": {"parentId": "p1"},
                "other": {"parentId": "p2", "childAccountId": "c9"},
            },
            codes={"123456": {"parentId": "p1"}, "654321": {"parentId": "p2"}},
        )
        _run_delete(fake_db, "p1")

        assert sorted(fake_db.recursive_deleted) == [
            "child_profiles/prof1",
            "child_profiles/prof2",
        ]
        assert "app_rules/p1" in fake_db.deleted_docs
        assert "pairing_codes/123456" in fake_db.deleted_docs
        assert "pairing_codes/654321" not in fake_db.deleted_docs
        # The paired child account is released, not deleted.
        assert fake_db.user_sets["users/c1"]["pairingStatus"] == "not_paired"

    def test_child_delete_removes_only_that_childs_profile(self):
        fake_db = _FakeDb(
            users={"c1": {"role": "child"}},
            profiles={
                "prof1": {"parentId": "p1", "childAccountId": "c1"},
                "prof2": {"parentId": "p1", "childAccountId": "c2"},
            },
        )
        _run_delete(fake_db, "c1")

        assert fake_db.recursive_deleted == ["child_profiles/prof1"]
        assert "app_rules/c1" not in fake_db.deleted_docs

    def test_cleanup_failure_keeps_the_login_so_the_delete_can_be_retried(self):
        fake_db = _FakeDb(
            users={"p1": {"role": "parent"}},
            profiles={"prof1": {"parentId": "p1"}},
        )

        def boom(ref):
            raise RuntimeError("firestore down")

        fake_db.recursive_delete = boom
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ), patch.object(svc.auth, "delete_user") as auth_delete, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ):
            try:
                svc.delete_user("p1")
            except RuntimeError:
                pass
        auth_delete.assert_not_called()
