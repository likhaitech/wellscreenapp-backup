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

    def update(self, data: dict) -> None:
        self._db._write(self, data, merge=True)

    def delete(self) -> None:
        self._db.docs.pop(self.path, None)

    def collection(self, name: str) -> "Collection":
        return Collection(self._db, f"{self.path}/{name}")


class Collection:
    """A collection, also used as a simple query (where / order_by / limit)."""

    def __init__(self, db: "FakeDb", name: str, filters=(), order=None, count=None):
        self._db, self._name = db, name
        self._filters, self._order, self._count = list(filters), order, count

    def document(self, doc_id: str | None = None) -> DocRef:
        return DocRef(self._db, self._name, doc_id or f"auto{next(_ids)}")

    def where(self, field=None, op=None, value=None, *, filter=None) -> "Collection":
        if filter is not None:
            field, op, value = filter.field_path, filter.op_string, filter.value
        return Collection(self._db, self._name, self._filters + [(field, op, value)],
                          self._order, self._count)

    def order_by(self, field, direction="ASCENDING") -> "Collection":
        return Collection(self._db, self._name, self._filters, (field, direction), self._count)

    def limit(self, count: int) -> "Collection":
        return Collection(self._db, self._name, self._filters, self._order, count)

    def stream(self, transaction: Any = None):
        prefix = self._name + "/"
        rows = []
        for path, data in self._db.docs.items():
            if not path.startswith(prefix) or "/" in path[len(prefix):]:
                continue
            ok = True
            for field, op, value in self._filters:
                have = data.get(field)
                ok = ok and ((op == "==" and have == value) or (op == "in" and have in value))
            if ok:
                rows.append(Snapshot(DocRef(self._db, self._name, path[len(prefix):]), data))
        if self._order:
            field, direction = self._order
            rows.sort(key=lambda r: r.to_dict().get(field), reverse=str(direction).upper().startswith("DESC"))
        return iter(rows[: self._count] if self._count else rows)


class Transaction:
    def __init__(self, db: "FakeDb"):
        self._db = db

    def get(self, ref):
        return ref.get(transaction=self)

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

    def recursive_delete(self, ref: DocRef) -> None:
        for path in [p for p in self.docs if p == ref.path or p.startswith(ref.path + "/")]:
            self.docs.pop(path)

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
