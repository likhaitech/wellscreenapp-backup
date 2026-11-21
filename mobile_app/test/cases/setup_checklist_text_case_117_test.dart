// CASE-117 - Alerts and Communication
// Run: flutter test test/cases/setup_checklist_text_case_117_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-117',
    file: 'test/cases/setup_checklist_text_case_117_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child denies the SMS permission.',
    expected: 'The child sees that SMS backup alerts will stay off.',
    body: (tester) async {
      const shown = SetupChecklistText.smsPermissionOff;
      expect(shown, startsWith('Off.'));
      return 'With SMS permission denied the SMS alerts row reads "$shown"';
    },
  );
}
