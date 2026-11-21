// CASE-042 - Device Pairing and Permission Setup
// Run: flutter test test/cases/setup_checklist_text_case_042_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-042',
    file: 'test/cases/setup_checklist_text_case_042_test.dart',
    codeTested: 'lib/services/android_app_service.dart',
    description: 'Child turns on the WellScreen Accessibility Service.',
    expected: 'The checklist shows “On. Restricted apps and websites are blocked.”',
    body: (tester) async {
      final shown = SetupChecklistText.accessibility(true);
      expect(shown, 'On. Restricted apps and websites are blocked.');
      return 'With the Accessibility Service on the checklist row reads "$shown"';
    },
  );
}
