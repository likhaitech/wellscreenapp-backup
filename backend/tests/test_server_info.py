"""record_deploy logs a server patch once per new version (Render restarts
the same build often on the free tier - those must not be logged again)."""
from __future__ import annotations

from unittest.mock import MagicMock

from app.services import server_info


def _db(stored: dict | None):
    snapshot = MagicMock()
    snapshot.exists = stored is not None
    snapshot.to_dict.return_value = stored or {}
    db = MagicMock()
    ref = db.collection.return_value.document.return_value
    ref.get.return_value = snapshot
    return db, ref


def test_new_version_is_recorded_and_logged():
    db, ref = _db({"server_version": "abc1234"})
    log = MagicMock()
    assert server_info.record_deploy(version="def5678", get_db=lambda: db, log=log)
    assert ref.set.call_args.args[0]["server_version"] == "def5678"
    assert log.call_args.kwargs["action"] == "server_patch_deployed"
    assert log.call_args.kwargs["details"] == {"version": "def5678", "previous": "abc1234"}


def test_same_version_restart_is_not_logged_again():
    db, ref = _db({"server_version": "def5678"})
    log = MagicMock()
    assert not server_info.record_deploy(version="def5678", get_db=lambda: db, log=log)
    ref.set.assert_not_called()
    log.assert_not_called()


def test_local_runs_are_never_recorded():
    get_db = MagicMock()
    assert not server_info.record_deploy(version="local", get_db=get_db, log=MagicMock())
    get_db.assert_not_called()


def test_server_info_shape():
    info = server_info.server_info()
    assert set(info) == {"version", "running_since"}
