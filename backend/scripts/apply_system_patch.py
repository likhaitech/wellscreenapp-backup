"""Apply a WellScreen system patch on the backend (developers only).

System patches are never applied from the mobile app. A developer prepares
a patch file and runs this tool with the backend's Firebase credentials;
the patch is validated, applied to system_settings/global and recorded in
System logs, where the administrator sees it.

    python scripts/apply_system_patch.py patches/maintenance_notice.json --check
    python scripts/apply_system_patch.py patches/maintenance_notice.json

Patch file format:
    {
      "version": "1.0.1",
      "description": "Maintenance notice for Saturday",
      "settings": {
        "maintenance_message": "Server maintenance tonight at 10 PM",
        "minimum_app_version": "1.0.0"
      }
    }

A rejected patch changes nothing and is logged as a warning.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow `python scripts/apply_system_patch.py` from inside backend/.
BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

ACTOR = "backend-patch-tool"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Apply a WellScreen system patch")
    parser.add_argument("patch_file", help="Path to the patch JSON file")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate only; change nothing",
    )
    args = parser.parse_args(argv)

    try:
        payload = json.loads(Path(args.patch_file).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Cannot read patch file: {exc}", file=sys.stderr)
        return 2

    from app.services.firebase_service import initialize_firebase
    from app.services.system_patch_service import PatchRejected, apply_patch

    initialize_firebase()
    try:
        result = apply_patch(payload, actor=ACTOR, validate_only=args.check or None)
    except PatchRejected as exc:
        print("Patch rejected - nothing changed:", file=sys.stderr)
        for error in exc.errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    if result["applied"]:
        print("Patch applied and recorded in System logs:")
    else:
        print("Patch is valid (nothing changed):")
    for key, value in result["changes"].items():
        print(f"  {key} = {value!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
