// CASE-138 - Emergency Access
// Run: flutter test test/cases/child_status_text_case_138_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-138',
    file: 'test/cases/child_status_text_case_138_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child opens the home screen after sending a request.',
    expected: 'The request shows “Waiting for your guardian to respond”.',
    body: (tester) async {
      final card = ChildStatusText.emergencyCard('requested');
      expect(card.subtitle, 'Waiting for your guardian to respond');
      return 'Card: "${card.title}" - "${card.subtitle}"';
    },
  );
}
