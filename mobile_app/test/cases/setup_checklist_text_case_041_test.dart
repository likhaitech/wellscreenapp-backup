// CASE-041 - Device Pairing and Permission Setup
// Run: flutter test test/cases/setup_checklist_text_case_041_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-041',
    file: 'test/cases/setup_checklist_text_case_041_test.dart',
    codeTested: 'lib/services/usage_dashboard_service.dart',
    description: 'Child grants Usage Access from the setup checklist.',
    expected: 'The checklist shows “Allowed. Screen time is read from this phone.”',
    body: (tester) async {
      final shown = SetupChecklistText.usageAccess(true);
      expect(shown, 'Allowed. Screen time is read from this phone.');
      return 'With Usage Access granted the checklist row reads "$shown"';
    },
  );
}
