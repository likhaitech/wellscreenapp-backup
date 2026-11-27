// CASE-043 - Device Pairing and Permission Setup
// Run: flutter test test/cases/setup_checklist_text_case_043_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-043',
    file: 'test/cases/setup_checklist_text_case_043_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child sets battery optimization for WellScreen to unrestricted.',
    expected: 'The checklist shows “Allowed. Battery saver will not stop WellScreen.”',
    body: (tester) async {
      final shown = SetupChecklistText.battery(true);
      expect(shown, 'Allowed. Battery saver will not stop WellScreen.');
      return 'With battery set to unrestricted the checklist row reads "$shown"';
    },
  );
}