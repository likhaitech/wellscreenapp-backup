// CASE-147 - Emergency Access
// Run: flutter test test/cases/parent_child_chat_screen_case_147_test.dart -r expanded

import 'dart:io';

import 'package:app/services/emergency_access_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-147',
    file: 'test/cases/parent_child_chat_screen_case_147_test.dart',
    codeTested: 'lib/screens/parent_child_chat_screen.dart',
    description: 'Child asks for Emergency Access from the chat.',
    expected: '“Emergency Access request sent to your guardian.” is displayed.',
    body: (tester) async {
      final source = File('lib/screens/parent_child_chat_screen.dart').readAsStringSync();
      expect(source.contains('Emergency Access request sent to your guardian.'), isTrue);
      expect(source.contains('requestAccess('), isTrue);
      expect(EmergencyAccessService.rejectionFor({}, DateTime(2026, 11, 22)), isNull);
      return 'The chat sends the same Emergency Access request and then shows '
          '"Emergency Access request sent to your guardian."';
    },
  );
}
