
"""Apply narrow WellScreen parent monitoring-alert backend updates.

Run from repo root:
    python wellscreen_backend_notifications_patch.py

This script never touches approval, app blocking, Firebase rules or secrets.
It aborts without writing if any required anchor is missing.
"""

from __future__ import annotations

from pathlib import Path
import re
import shutil
from datetime import datetime

ROOT = Path.cwd()
MONITOR = ROOT / "backend/app/services/monitoring_alerts_service.py"
PUSH = ROOT / "backend/app/services/notification_service.py"


def load(path: Path) -> tuple[str, str]:
    raw = path.read_bytes().decode("utf-8-sig")
    return raw.replace("\r\n", "\n"), (
        "\r\n" if "\r\n" in raw else "\n"
    )


def save(path: Path, contents: str, nl: str) -> None:
    backup = path.with_name(
        path.name
        + ".backup-"
        + datetime.now().strftime("%Y%m%d-%H%M%S")
    )

    shutil.copy2(path, backup)

    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(contents.replace("\n", nl))

    print(
        f"Updated {path.relative_to(ROOT)} "
        f"(backup {backup.name})"
    )


m, mn = load(MONITOR)
p, pn = load(PUSH)

old_m, old_p = m, p

# Ensure event types and descriptions are updated together.
if '"usage_warning_threshold"' not in m:
    marker = '    "monitoring_permission_disabled",'

    if m.count(marker) != 1:
        raise SystemExit(
            "Monitoring EVENT_TYPES anchor missing; "
            "no changes written."
        )

    m = m.replace(
        marker,
        marker
        + '\n    "usage_warning_threshold", '
        '"usage_high_threshold", '
        '"unhealthy_usage_pattern",',
        1,
    )


if '"usage_warning_threshold":' not in m:
    pattern = re.compile(
        r'(?m)^(?P<indent>\s*)"monitoring_permission_disabled":.*,$'
    )

    matches = list(pattern.finditer(m))

    if len(matches) != 1:
        raise SystemExit(
            "Monitoring descriptions anchor missing; "
            "no changes written."
        )

    anchor = matches[0]
    spaces = anchor.group("indent").replace("\n", "")

    additions = (
        "\n"
        + spaces
        + '"usage_warning_threshold": '
        '("Screen-time warning", f"Device usage reached {label}."),'
        "\n"
        + spaces
        + '"usage_high_threshold": '
        '("High screen-time alert", f"Device usage reached {label}."),'
        "\n"
        + spaces
        + '"unhealthy_usage_pattern": '
        '("Unhealthy usage pattern", '
        'f"A concerning usage pattern was detected: {label}."),'
    )

    m = m[:anchor.end()] + additions + m[anchor.end():]


# Create a durable parent notification inbox record.
if '"monitoring_alert"' not in m:
    anchor = (
        "    push = _push("
        "parent_uid=parent_uid, title=title, message=body,"
    )

    if m.count(anchor) != 1:
        raise SystemExit(
            "Monitoring push anchor missing; "
            "no changes written."
        )

    entry = '''    # One durable parent inbox item per monitoring event.
    try:
        inbox_ref = (
            db.collection("users")
            .document(parent_uid)
            .collection("notifications")
            .document(f"monitor_{profile_id}_{alert_id}")
        )

        inbox_ref.create({
            "type": "monitoring_alert",
            "kind": kind,
            "title": title,
            "body": body,
            "childProfileId": profile_id,
            "monitoringAlertId": alert_id,
            "senderUid": "",
            "createdAt": _utcnow(),
            "readAt": None,
        })

    except (AlreadyExists, Conflict):
        pass

    except Exception:
        log.exception(
            "Could not persist parent monitoring inbox record"
        )

'''

    m = m.replace(anchor, entry + anchor, 1)


# Add fallback FCM token lookup for parent notifications.
if "token_field = next(" not in p:
    anchor = '    fcm_token = recipient_data.get("fcmToken")'

    if p.count(anchor) != 1:
        raise SystemExit(
            "Alert token anchor missing; "
            "no changes written."
        )

    p = p.replace(
        anchor,
        '''    token_field = next(
        (
            field
            for field in (
                "fcmToken",
                "chatFcmToken",
                "limitNotificationToken",
            )
            if recipient_data.get(field)
        ),
        None,
    )

    fcm_token = (
        recipient_data.get(token_field)
        if token_field
        else None
    )''',
        1,
    )

    anchor = (
        'db.collection("users").document(parent_uid)'
        '.update({"fcmToken": None})'
    )

    if p.count(anchor) != 1:
        raise SystemExit(
            "Alert unregistered-token anchor missing; "
            "no changes written."
        )

    p = p.replace(
        anchor,
        'db.collection("users").document(parent_uid)'
        '.update({token_field: None})',
        1,
    )


# Validate both files before modifying either.
compile(m, str(MONITOR), "exec")
compile(p, str(PUSH), "exec")

if m != old_m:
    save(MONITOR, m, mn)
else:
    print("Monitoring backend already patched.")

if p != old_p:
    save(PUSH, p, pn)
else:
    print("Notification backend already patched.")

print(
    "Success. Run git diff to verify "
    "the backend changes before deploying."
)
