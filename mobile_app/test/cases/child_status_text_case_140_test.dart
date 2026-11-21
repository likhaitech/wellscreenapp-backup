// CASE-140 - Emergency Access
// Run: flutter test test/cases/child_status_text_case_140_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-140',
    file: 'test/cases/child_status_text_case_140_test.dart',
    codeTested: 'lib/services/emergency_access_service.dart',
    description: 'Guardian denies the request.',
    expected: 'Child sees “Your last request was denied. You can ask again.”',
    body: (tester) async {
      final card = ChildStatusText.emergencyCard('denied');
      expect(card.subtitle, 'Your last request was denied. You can ask again.');
      return 'After the guardian denies: "${card.subtitle}"';
    },
  );
}
