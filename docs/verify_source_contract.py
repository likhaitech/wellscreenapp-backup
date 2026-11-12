"""Static contract sanity check only; NOT an HTTP or Firebase integration test."""
from pathlib import Path
import ast

root = Path(__file__).resolve().parents[1]
router = (root / 'backend/app/routes/parent_child_chat.py').read_text()
chat = (root / 'mobile_app/lib/screens/parent_child_chat_screen.dart').read_text()
service = (root / 'backend/app/services/chat_access_service.py').read_text()
main = (root / 'backend/app/main.py').read_text()

ast.parse(router)
ast.parse(service)
ast.parse(main)
assert '@router.post("/chat/requests/{profile_id}/{request_id}/decision")' in router
assert "/chat/requests/${widget.childProfileId}/$requestId/decision" in chat
assert '@router.get("/chat/health")' in router
assert '@router.post("/chat/events/{profile_id}/{kind}/{event_id}/dispatch")' in router
assert 'app.include_router(parent_child_chat_router)' in main
assert 'notificationState' in service and 'decisionNotificationState' in service
print('Static source contract checks passed. Check Render deployment separately.')
