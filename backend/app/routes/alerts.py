import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.models.alert import AlertNotifyRequest, AlertNotifyResponse
from app.services.device_admin_alert_service import (
    DEVICE_ADMIN_ALERTS,
    record_device_admin_alert,
)
from app.services.notification_service import (
    NoDeviceTokenError,
    NotAuthorizedError,
    send_alert_notification,
)
from app.services.user_auth_service import require_user

router = APIRouter(prefix="/alerts", tags=["Alerts"])

logger = logging.getLogger(__name__)


@router.post("/notify", response_model=AlertNotifyResponse)
def notify(
    payload: AlertNotifyRequest,
    current_user: dict = Depends(require_user),
):
    caller_uid = current_user.get("uid")
    result: dict | None = None
    unexpected_error = False

    try:
        result = send_alert_notification(
            caller_uid=caller_uid,
            parent_uid=payload.parent_uid,
            title=payload.title,
            body=payload.body,
            data={"alertType": payload.alert_type, **(payload.data or {})},
        )
    except NotAuthorizedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        )
    except NoDeviceTokenError as exc:
        # Not a server error - the parent just hasn't opened the app with
        # notifications set up yet. 200 with a "failed" status lets the
        # caller distinguish "we tried and it didn't work" from "the server
        # is broken", matching AlertNotifyResponse's shape either way.
        result = {"status": "failed", "error": str(exc)}
    except Exception:
        # FIX: unlike admin_users.py/admin_logs.py/admin_overview.py (all
        # gated by require_admin - an already-trusted caller seeing their
        # own action's error text is low-stakes), this route is gated by
        # require_user, so ANY signed-in parent or child hits this path -
        # e.g. a transient Firestore hiccup inside caller_may_notify()/
        # send_alert_notification() that isn't one of the two typed
        # exceptions above. Returning str(exc) here would hand a regular,
        # non-admin user raw internal exception text (Firestore paths,
        # gRPC error details). Log the real exception server-side instead
        # and return a generic message to the client.
        logger.exception("Unexpected error sending alert notification")
        unexpected_error = True

    # Device Admin alerts also get an in-app record, even if the push failed.
    if payload.alert_type in DEVICE_ADMIN_ALERTS:
        try:
            record_device_admin_alert(
                caller_uid=caller_uid,
                parent_uid=payload.parent_uid,
                alert_type=payload.alert_type,
                data=payload.data,
                push_status=(result or {}).get("status", "failed"),
            )
        except Exception:
            logger.exception("Could not save Device Admin alert record")

    if unexpected_error or result is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send alert notification.",
        )
    return AlertNotifyResponse(**result)
