"""In-memory stand-in for Firestore so the real pairing service code runs
without a Firebase project. Documents are plain dicts keyed by path.
Transactions apply their writes straight away (enough for one caller)."""
from __future__ import annotations

import itertools
from typing import Any

from firebase_admin import firestore
from google.api_core.exceptions import AlreadyExists

_ids = itertools.count(1)


class Snapshot:
    def __init__(self, ref: "DocRef", data: dict | None):
        self.reference = ref
        self.id = ref.id
        self.exists = data is not None
        self._data = data

    def to_dict(self) -> dict | None:
        return None if self._data is None else dict(self._data)


class DocRef:
    def __init__(self, db: "FakeDb", collection: str, doc_id: str):
        self._db, self.id = db, doc_id
        self.path = f"{collection}/{doc_id}"

    def get(self, transaction: Any = None) -> Snapshot:
        return Snapshot(self, self._db.docs.get(self.path))

    def set(self, data: dict, merge: bool = False) -> None:
        self._db._write(self, data, merge=merge)


class Collection:
    def __init__(self, db: "FakeDb", name: str):
        self._db, self._name = db, name

    def document(self, doc_id: str | None = None) -> DocRef:
        return DocRef(self._db, self._name, doc_id or f"auto{next(_ids)}")


class Transaction:
    def __init__(self, db: "FakeDb"):
        self._db = db

    def create(self, ref: DocRef, data: dict) -> None:
        if ref.path in self._db.docs:
            raise AlreadyExists(ref.path)
        self._db._write(ref, data)

    def set(self, ref: DocRef, data: dict, merge: bool = False) -> None:
        self._db._write(ref, data, merge=merge)

    def update(self, ref: DocRef, data: dict) -> None:
        self._db._write(ref, data, merge=True)


class FakeDb:
    def __init__(self, docs: dict | None = None):
        self.docs: dict[str, dict] = dict(docs or {})

    def collection(self, name: str) -> Collection:
        return Collection(self, name)

    def transaction(self) -> Transaction:
        return Transaction(self)

    def _write(self, ref: DocRef, data: dict, merge: bool = False) -> None:
        base = dict(self.docs.get(ref.path, {})) if merge else {}
        for key, value in data.items():
            if value is firestore.DELETE_FIELD:
                base.pop(key, None)
            else:
                base[key] = value
        self.docs[ref.path] = base


def install(monkeypatch, pairing_module, docs: dict | None = None) -> FakeDb:
    """Point the real pairing service at a fake database."""
    db = FakeDb(docs)
    monkeypatch.setattr(pairing_module, "get_firestore_client", lambda: db)
    # Firestore's @transactional retries a function inside a real
    # transaction; with the fake every write applies at once.
    monkeypatch.setattr(pairing_module, "transactional", lambda fn: fn)
    return db
