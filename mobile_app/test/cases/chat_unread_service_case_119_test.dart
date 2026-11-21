// CASE-119 - Alerts and Communication
// Run: flutter test test/cases/chat_unread_service_case_119_test.dart -r expanded

import 'package:app/services/chat_unread_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-119',
    file: 'test/cases/chat_unread_service_case_119_test.dart',
    codeTested: 'lib/services/chat_unread_service.dart',
    description: 'Child replies in Chat.',
    expected: 'The guardian receives the reply with an unread indicator.',
    body: (tester) async {
      final seen = DateTime(2026, 11, 22, 10, 0).millisecondsSinceEpoch;
      final messages = [
        {'senderId': 'parent-1', 'createdAt': DateTime(2026, 11, 22, 10, 0)},
        {'senderId': 'child-1', 'createdAt': DateTime(2026, 11, 22, 10, 5)},
      ];
      final newest = ChatUnreadService.newestFromOther(messages, 'parent-1');
      expect(ChatUnreadService.isUnread(newest, seen), isTrue);
      expect(ChatUnreadService.isUnread(newest, newest), isFalse);
      return 'The child\'s 10:05 reply is newer than the guardian last saw, so '
          'the unread dot shows; it clears once the chat is opened';
    },
  );
}
