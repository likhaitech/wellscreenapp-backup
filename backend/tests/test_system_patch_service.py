"""System patches are validated, applied and logged on the backend only
(scripts/apply_system_patch.py). The prepared patch files in patches/ are
checked here too, so the defense demo files are known to behave."""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from app.services.system_patch_service import PatchRejected, apply_patch

PATCHES = Path(__file__).resolve().parents[1] / "patches"


def _run(payload, **kwargs):
    update = MagicMock(return_value={"maintenance_message": "x"})
    log = MagicMock()
    result = apply_patch(payload, actor="tool", update=update, log=log, **kwargs)
    return result, update, log


def test_valid_patch_is_applied_and_logged():
    result, update, log = _run({
        "version": "1.0.1",
        "settings": {"maintenance_message": "Maintenance at 10 PM"},
    })
    assert result["applied"] is True
    update.assert_called_once_with(
        {"maintenance_message": "Maintenance at 10 PM"}, updated_by="tool"
    )
    assert log.call_args.kwargs["action"] == "system_patch_applied"


def test_check_only_changes_nothing():
    result, update, log = _run(
        {"settings": {"minimum_app_version": "1.0.1"}}, validate_only=True
    )
    assert result == {
        "valid": True,
        "applied": False,
        "changes": {"minimum_app_version": "1.0.1"},
    }
    update.assert_not_called()
    log.assert_not_called()


@pytest.mark.parametrize("payload", [
    {"settings": {"minimum_app_version": "1.4"}},
    {"settings": {"minimum_app_version": 140}},
    {"settings": {"focus_mode_enabled": False}},
    {"settings": {"maintenance_message": "x" * 201}},
    {"settings": {}},
    "not a patch",
])
def test_rejected_patch_changes_nothing_and_logs_a_warning(payload):
    update = MagicMock()
    log = MagicMock()
    with pytest.raises(PatchRejected):
        apply_patch(payload, actor="tool", update=update, log=log)
    update.assert_not_called()
    assert log.call_args.kwargs["level"] == "warning"
    assert log.call_args.kwargs["action"] == "system_patch_rejected"


@pytest.mark.parametrize("name", [
    "maintenance_notice.json",
    "clear_maintenance_notice.json",
    "require_update_example.json",
    "allow_all_versions.json",
])
def test_prepared_patch_files_are_valid(name):
    payload = json.loads((PATCHES / name).read_text(encoding="utf-8"))
    result, _, _ = _run(payload, validate_only=True)
    assert result["valid"] is True


def test_prepared_invalid_example_is_rejected():
    payload = json.loads((PATCHES / "invalid_example.json").read_text(encoding="utf-8"))
    with pytest.raises(PatchRejected) as exc:
        _run(payload)
    assert len(exc.value.errors) == 2


def test_backend_tool_check_and_apply(tmp_path, capsys):
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "apply_system_patch",
        Path(__file__).resolve().parents[1] / "scripts" / "apply_system_patch.py",
    )
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)

    patch_file = tmp_path / "p.json"
    patch_file.write_text(json.dumps(
        {"settings": {"maintenance_message": "Hello"}}
    ), encoding="utf-8")

    with patch("app.services.firebase_service.initialize_firebase"), \
         patch("app.services.system_patch_service.update_system_settings",
               return_value={}) as upd, \
         patch("app.services.system_patch_service.create_system_log") as log:
        # apply_patch's defaults were bound at import; patch them on the function.
        import app.services.system_patch_service as svc
        defaults = svc.apply_patch.__kwdefaults__
        old = dict(defaults)
        defaults["update"], defaults["log"] = upd, log
        try:
            assert tool.main([str(patch_file), "--check"]) == 0
            upd.assert_not_called()
            assert tool.main([str(patch_file)]) == 0
            upd.assert_called_once()
            assert log.call_args.kwargs["actor_uid"] == "backend-patch-tool"
            bad = tmp_path / "bad.json"
            bad.write_text('{"settings": {"minimum_app_version": "1.4"}}', encoding="utf-8")
            assert tool.main([str(bad)]) == 1
        finally:
            defaults.update(old)
    out = capsys.readouterr()
    assert "Patch applied" in out.out
    assert "nothing changed" in out.err
