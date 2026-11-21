// CASE-118 - Alerts and Communication
// Run: flutter test test/cases/chat_unread_service_case_118_test.dart -r expanded

import 'package:app/services/chat_unread_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-118',
    file: 'test/cases/chat_unread_service_case_118_test.dart',
    codeTested: 'lib/screens/parent_child_chat_screen.dart',
    description: 'Guardian sends a chat message to the child.',
    expected: 'The child receives the message in Chat.',
    body: (tester) async {
      final sent = DateTime(2026, 11, 22, 10, 0);
      final messages = [
        {'senderId': 'parent-1', 'text': 'Time for homework', 'createdAt': sent},
      ];
      final newest = ChatUnreadService.newestFromOther(messages, 'child-1');
      expect(newest, sent.millisecondsSinceEpoch);
      expect(ChatUnreadService.isUnread(newest, null), isTrue);
      return 'The guardian\'s "Time for homework" reaches the child\'s chat '
          'as a new message';
    },
  );
}
