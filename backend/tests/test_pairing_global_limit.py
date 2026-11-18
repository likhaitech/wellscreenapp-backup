"""Global limit on wrong pairing codes across ALL accounts (F13).
Firestore is faked - no real project is touched."""
from __future__ import annotations

import datetime as dt
from unittest.mock import MagicMock

import pytest

from app.services import pairing_service as pairing

NOW = dt.datetime(2026, 11, 18, 10, 0, tzinfo=dt.timezone.utc)


class TestWindowState:
    def test_counts_inside_the_window(self):
        start = NOW - dt.timedelta(minutes=5)
        assert pairing._window_state(
            {"windowStartedAt": start, "attemptCount": 7}, NOW
        ) == (start, 7)

    def test_resets_after_the_window(self):
        old = NOW - pairing.REDEMPTION_WINDOW
        assert pairing._window_state(
            {"windowStartedAt": old, "attemptCount": 49}, NOW
        ) == (NOW, 0)

    def test_malformed_data_starts_fresh(self):
        assert pairing._window_state({"attemptCount": "lots"}, NOW) == (NOW, 0)
        assert pairing._window_state({"attemptCount": True}, NOW) == (NOW, 0)
        assert pairing._window_state({}, NOW) == (NOW, 0)


def _snapshot(data):
    snap = MagicMock()
    snap.exists = data is not None
    snap.to_dict.return_value = data
    return snap


class FakeDb:
    """Minimal Firestore stand-in: documents are plain dicts."""

    def __init__(self, docs):
        self.docs = docs
        self.writes = {}

    def collection(self, name):
        db = self

        class Col:
            def document(self, doc_id):
                path = f"{name}/{doc_id}"
                ref = MagicMock()
                ref.path = path
                ref.get.side_effect = lambda transaction=None: _snapshot(
                    db.docs.get(path)
                )
                return ref

        return Col()

    def transaction(self):
        db = self
        tx = MagicMock()

        def set_doc(ref, data, merge=False):
            db.writes[ref.path] = data
            db.docs[ref.path] = {**db.docs.get(ref.path, {}), **data}

        tx.set.side_effect = set_doc
        return tx


@pytest.fixture
def fake_env(monkeypatch):
    docs = {"users/child-1": {"role": "child"}}
    db = FakeDb(docs)
    monkeypatch.setattr(pairing, "get_firestore_client", lambda: db)
    monkeypatch.setattr(pairing, "_now", lambda: NOW)
    # Run "transactional" functions directly with the fake transaction.
    monkeypatch.setattr(pairing, "transactional", lambda fn: fn)
    monkeypatch.setattr(pairing, "_consume_redemption_attempt", lambda *_: None)
    return db


GLOBAL = f"pairing_attempt_limits/{pairing.GLOBAL_FAILURES_DOC_ID}"


def test_wrong_code_is_counted_globally(fake_env):
    with pytest.raises(pairing.PairingCodeInvalidError, match="not found"):
        pairing.redeem_pairing_code(child_uid="child-1", code="123456")

    assert fake_env.docs[GLOBAL]["attemptCount"] == 1


def test_wrong_codes_from_many_accounts_add_up(fake_env):
    for i in range(3):
        fake_env.docs[f"users/child-{i}"] = {"role": "child"}
        with pytest.raises(pairing.PairingCodeInvalidError):
            pairing.redeem_pairing_code(child_uid=f"child-{i}", code="123456")

    assert fake_env.docs[GLOBAL]["attemptCount"] == 3


def test_redemptions_refused_once_the_global_budget_is_used(fake_env):
    fake_env.docs[GLOBAL] = {
        "windowStartedAt": NOW - dt.timedelta(minutes=1),
        "attemptCount": pairing.MAX_GLOBAL_FAILED_REDEMPTIONS,
    }

    with pytest.raises(pairing.PairingRateLimitError, match="paused"):
        pairing.redeem_pairing_code(child_uid="child-1", code="123456")

    # Refused before the code was even looked up, and not counted again.
    assert fake_env.docs[GLOBAL]["attemptCount"] == (
        pairing.MAX_GLOBAL_FAILED_REDEMPTIONS
    )


def test_budget_comes_back_after_the_window(fake_env):
    fake_env.docs[GLOBAL] = {
        "windowStartedAt": NOW - pairing.REDEMPTION_WINDOW,
        "attemptCount": pairing.MAX_GLOBAL_FAILED_REDEMPTIONS,
    }

    with pytest.raises(pairing.PairingCodeInvalidError):
        pairing.redeem_pairing_code(child_uid="child-1", code="123456")

    assert fake_env.docs[GLOBAL]["attemptCount"] == 1


def test_expired_code_counts_as_a_failed_guess(fake_env):
    fake_env.docs["pairing_codes/123456"] = {
        "parentId": "parent-1",
        "childId": "profile-1",
        "expiresAt": NOW - dt.timedelta(minutes=1),
        "status": "active",
    }
    fake_env.docs["child_profiles/profile-1"] = {"parentId": "parent-1"}
    fake_env.docs["users/parent-1"] = {"role": "parent"}

    with pytest.raises(pairing.PairingCodeInvalidError, match="expired"):
        pairing.redeem_pairing_code(child_uid="child-1", code="123456")

    assert fake_env.docs[GLOBAL]["attemptCount"] == 1


def test_counter_failure_never_hides_the_real_error(fake_env, monkeypatch):
    def broken(_db):
        raise RuntimeError("firestore unavailable")

    monkeypatch.setattr(pairing, "_record_global_failure", broken)

    with pytest.raises(pairing.PairingCodeInvalidError, match="not found"):
        pairing.redeem_pairing_code(child_uid="child-1", code="123456")


def test_invalid_code_is_still_a_normal_pairing_error():
    # Routes map PairingError to HTTP 400, so the app message is unchanged.
    assert issubclass(pairing.PairingCodeInvalidError, pairing.PairingError)
