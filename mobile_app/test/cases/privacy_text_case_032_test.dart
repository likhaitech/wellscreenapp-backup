// CASE-032 - Profile Management
// Run: flutter test test/cases/privacy_text_case_032_test.dart -r expanded

import 'package:app/services/privacy_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-032',
    file: 'test/cases/privacy_text_case_032_test.dart',
    codeTested: 'lib/services/privacy_text.dart',
    description: 'Child opens “Monitoring is on”.',
    expected: 'The child sees what the guardian can see and what WellScreen never reads.',
    body: (tester) async {
      expect(PrivacyText.childWebsites, contains('not full addresses'));
      expect(PrivacyText.childPageCheck, contains('never saved or sent'));
      return 'The child sheet lists website names (not full addresses or '
          'typing) and says page words are never saved or sent';
    },
  );
}
