"""Email verification gate for linking a child.

Anyone can create a WellScreen account, but a guardian must have a
verified email before they can generate a pairing code. A child can only
link by redeeming a code from such a guardian, so no child can be linked
to an account with a fake or mistyped email. Children are not asked to
verify: many have no email of their own.

The check reads the account from Firebase Auth on every call (not the ID
token's email_verified claim), so it takes effect the moment the user
opens the verification link, with no need to refresh the token.

Accounts created before ENFORCED_FROM_MS keep pairing as before (test and
study accounts made before this rule existed).
"""
from __future__ import annotations

from .firebase_service import get_auth_module

# 18 Nov 2026, 6:00 PM Manila time (10:00 UTC), in milliseconds.
ENFORCED_FROM_MS = 1_794_996_000_000

EMAIL_NOT_VERIFIED_MESSAGE = (
    "Verify your email before linking a child. Open the link we sent to "
    "your inbox, then try again."
)


class EmailNotVerifiedError(Exception):
    """The account must verify its email before this action."""


def ensure_email_verified(uid: str, *, auth_module=None) -> None:
    firebase_auth = auth_module or get_auth_module()
    user = firebase_auth.get_user(uid)

    if user.email_verified:
        return

    metadata = getattr(user, "user_metadata", None)
    created_ms = getattr(metadata, "creation_timestamp", None)
    if isinstance(created_ms, (int, float)) and created_ms < ENFORCED_FROM_MS:
        return

    raise EmailNotVerifiedError(EMAIL_NOT_VERIFIED_MESSAGE)
