from __future__ import annotations

import concurrent.futures
import datetime as dt
import os
import uuid

import pytest

from app.services import pairing_service as pairing
from app.services.firebase_service import get_firestore_client


pytestmark = pytest.mark.skipif(
    not os.getenv("FIRESTORE_EMULATOR_HOST"),
    reason="Requires the Firestore Emulator.",
)


@pytest.fixture
def pairing_context():
    db = get_firestore_client()
    run_id = uuid.uuid4().hex
    tracked_refs = []

    def track(collection: str, document_id: str):
        ref = db.collection(collection).document(document_id)
        tracked_refs.append(ref)
        return ref

    def create_user(role: str) -> str:
        uid = f"it-{run_id}-{role}-{uuid.uuid4().hex[:8]}"

        user_ref = track("users", uid)
        user_ref.set({
            "uid": uid,
            "email": f"{uid}@example.test",
            "fullName": f"Test {role.title()}",
            "role": role,
        })

        if role == "child":
            track("pairing_attempt_limits", uid)

        return uid

    yield {
        "db": db,
        "create_user": create_user,
        "track": track,
    }

    for ref in reversed(tracked_refs):
        try:
            ref.delete()
        except Exception:
            pass


def create_test_pairing(context, parent_uid: str):
    result = pairing.generate_pairing_code(
        parent_uid=parent_uid,
        child_name="Integration Test Child",
    )

    context["track"]("pairing_codes", result["code"])
    context["track"](
        "child_profiles",
        result["childProfileId"],
    )

    return result


def test_generate_pairing_code_creates_documents(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")

    result = create_test_pairing(context, parent_uid)

    assert len(result["code"]) == 6
    assert result["code"].isdigit()

    code_doc = (
        db.collection("pairing_codes")
        .document(result["code"])
        .get()
    )

    profile_doc = (
        db.collection("child_profiles")
        .document(result["childProfileId"])
        .get()
    )

    assert code_doc.exists
    assert profile_doc.exists

    assert code_doc.get("status") == "active"
    assert code_doc.get("parentId") == parent_uid

    assert profile_doc.get("parentId") == parent_uid
    assert profile_doc.get("pairingStatus") == "waiting"


def test_redeem_pairing_code_connects_all_documents(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")
    child_uid = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    result = pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=generated["code"],
    )

    assert result["status"] == "connected"
    assert result["parentId"] == parent_uid
    assert result["childProfileId"] == generated["childProfileId"]

    code_doc = (
        db.collection("pairing_codes")
        .document(generated["code"])
        .get()
    ).to_dict()

    profile_doc = (
        db.collection("child_profiles")
        .document(generated["childProfileId"])
        .get()
    ).to_dict()

    child_doc = (
        db.collection("users")
        .document(child_uid)
        .get()
    ).to_dict()

    assert code_doc["status"] == "connected"
    assert code_doc["childAccountId"] == child_uid

    assert profile_doc["pairingStatus"] == "connected"
    assert profile_doc["childAccountId"] == child_uid

    assert child_doc["pairedParentId"] == parent_uid
    assert child_doc["pairedChildProfileId"] == generated["childProfileId"]
    assert child_doc["pairingStatus"] == "connected"

    # A retry from the same child must be safe.
    retry = pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=generated["code"],
    )

    assert retry["status"] == "connected"


def test_expired_pairing_code_is_rejected(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")
    child_uid = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    code_ref = (
        db.collection("pairing_codes")
        .document(generated["code"])
    )

    code_ref.update({
        "expiresAt": (
            dt.datetime.now(dt.timezone.utc)
            - dt.timedelta(minutes=1)
        )
    })

    with pytest.raises(pairing.PairingError, match="expired"):
        pairing.redeem_pairing_code(
            child_uid=child_uid,
            code=generated["code"],
        )

    assert code_ref.get().get("status") == "active"


def test_second_child_cannot_redeem_used_code(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")
    first_child = context["create_user"]("child")
    second_child = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    pairing.redeem_pairing_code(
        child_uid=first_child,
        code=generated["code"],
    )

    with pytest.raises(pairing.PairingConflictError):
        pairing.redeem_pairing_code(
            child_uid=second_child,
            code=generated["code"],
        )

    second_child_doc = (
        db.collection("users")
        .document(second_child)
        .get()
        .to_dict()
    )

    assert second_child_doc.get("pairedParentId") is None
    assert second_child_doc.get("pairedChildProfileId") is None


def test_redemption_attempt_limit_is_enforced(pairing_context):
    context = pairing_context

    child_uid = context["create_user"]("child")

    # 000000 is outside the generated code range (100000-999999).
    for _ in range(pairing.MAX_REDEMPTION_ATTEMPTS):
        with pytest.raises(
            pairing.PairingError,
            match="not found",
        ):
            pairing.redeem_pairing_code(
                child_uid=child_uid,
                code="000000",
            )

    with pytest.raises(pairing.PairingRateLimitError):
        pairing.redeem_pairing_code(
            child_uid=child_uid,
            code="000000",
        )


def test_concurrent_redemption_allows_only_one_child(pairing_context):
    import threading

    context = pairing_context

    parent_uid = context["create_user"]("parent")
    child_one = context["create_user"]("child")
    child_two = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    barrier = threading.Barrier(2)

    def attempt(child_uid):
        barrier.wait(timeout=15)

        try:
            pairing.redeem_pairing_code(
                child_uid=child_uid,
                code=generated["code"],
            )
            return "success"

        except pairing.PairingConflictError:
            return "conflict"

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=2
    ) as executor:
        results = list(executor.map(
            attempt,
            [child_one, child_two],
        ))

    assert results.count("success") == 1
    assert results.count("conflict") == 1

    db = context["db"]

    code_doc = (
        db.collection("pairing_codes")
        .document(generated["code"])
        .get()
        .to_dict()
    )

    assert code_doc["status"] == "connected"
    assert code_doc["childAccountId"] in {
        child_one,
        child_two,
    }


def test_unpair_resets_child_and_allows_repair(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")
    child_uid = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=generated["code"],
    )

    result = pairing.unpair_child_device(
        parent_uid=parent_uid,
        child_profile_id=generated["childProfileId"],
    )

    assert result["status"] == "unpaired"

    child_doc = (
        db.collection("users")
        .document(child_uid)
        .get()
        .to_dict()
    )

    assert child_doc["pairingStatus"] == "not_paired"
    assert child_doc.get("pairedParentId") is None
    assert child_doc.get("pairedChildProfileId") is None
    assert child_doc.get("pairingCode") is None

    profile_doc = (
        db.collection("child_profiles")
        .document(generated["childProfileId"])
        .get()
        .to_dict()
    )

    assert profile_doc["pairingStatus"] == "unpaired"
    assert profile_doc.get("childAccountId") is None

    code_doc = (
        db.collection("pairing_codes")
        .document(generated["code"])
        .get()
        .to_dict()
    )

    assert code_doc["status"] == "revoked"

    with pytest.raises(pairing.PairingError):
        pairing.redeem_pairing_code(
            child_uid=child_uid,
            code=generated["code"],
        )

    new_pairing = create_test_pairing(context, parent_uid)

    repaired = pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=new_pairing["code"],
    )

    assert repaired["status"] == "connected"

    # Retrying the old removal must not unlink the new pairing.
    pairing.unpair_child_device(
        parent_uid=parent_uid,
        child_profile_id=generated["childProfileId"],
    )

    current_child = (
        db.collection("users")
        .document(child_uid)
        .get()
        .to_dict()
    )

    assert (
        current_child["pairedChildProfileId"]
        == new_pairing["childProfileId"]
    )


def test_other_parent_cannot_unpair_child(pairing_context):
    context = pairing_context
    db = context["db"]

    parent_uid = context["create_user"]("parent")
    other_parent = context["create_user"]("parent")
    child_uid = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=generated["code"],
    )

    with pytest.raises(pairing.PairingForbiddenError):
        pairing.unpair_child_device(
            parent_uid=other_parent,
            child_profile_id=generated["childProfileId"],
        )

    child_doc = (
        db.collection("users")
        .document(child_uid)
        .get()
        .to_dict()
    )

    assert child_doc["pairingStatus"] == "connected"
    assert child_doc["pairedParentId"] == parent_uid


def test_child_cannot_unpair_own_device(pairing_context):
    context = pairing_context

    parent_uid = context["create_user"]("parent")
    child_uid = context["create_user"]("child")

    generated = create_test_pairing(context, parent_uid)

    pairing.redeem_pairing_code(
        child_uid=child_uid,
        code=generated["code"],
    )

    with pytest.raises(pairing.PairingForbiddenError):
        pairing.unpair_child_device(
            parent_uid=child_uid,
            child_profile_id=generated["childProfileId"],
        )