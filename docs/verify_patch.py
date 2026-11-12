from pathlib import Path
import ast
root=Path(__file__).resolve().parents[1]
back=(root/'backend/app/services/chat_access_service.py').read_text()
route=(root/'backend/app/routes/parent_child_chat.py').read_text()
dart=(root/'mobile_app/lib/services/chat_notifications_service.dart').read_text()
main=(root/'mobile_app/lib/main.dart').read_text()
for code in (back,route): ast.parse(code)
assert 'messaging.send(' in back
assert 'chatFcmToken' in back and 'chatFcmToken' in dart
assert 'notification_count=_unread_count' in back
assert '/chat/push/status' in route
assert 'authStateChanges().listen' in dart
assert 'onTokenRefresh.listen' in dart
assert 'requestPermission' in dart
assert 'getToken' in dart
assert "'chatNotificationPermission'" in dart
assert 'FirebaseMessaging.onMessage.listen' in dart
assert 'getInitialMessage' in dart
assert 'ChatNotificationsService.instance.initialize()' in main
assert 'ChatNotificationsService.navigatorKey' in main
print('Patch source contracts verified; device delivery NOT tested.')
