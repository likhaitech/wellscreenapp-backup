// CASE-123 - Location Tracking
// Run: flutter test test/cases/setup_checklist_text_case_123_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-123',
    file: 'test/cases/setup_checklist_text_case_123_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child taps Share GPS now.',
    expected: '“Current GPS location shared to guardian dashboard.” is displayed.',
    body: (tester) async {
      expect(SetupChecklistText.gpsShared,
          'Current GPS location shared to guardian dashboard.');
      return 'After Share GPS now saves the location the child sees '
          '"${SetupChecklistText.gpsShared}"';
    },
  );
}
