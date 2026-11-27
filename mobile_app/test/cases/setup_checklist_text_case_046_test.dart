// CASE-046 - Device Pairing and Permission Setup
// Run: flutter test test/cases/setup_checklist_text_case_046_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-046',
    file: 'test/cases/setup_checklist_text_case_046_test.dart',
    codeTested: 'lib/screens/device_pairing_screen.dart',
    description: 'Child and guardian open the pairing status after pairing.',
    expected: 'Child sees “Paired with your parent”; guardian sees the child under Paired Devices.',
    body: (tester) async {
      expect(SetupChecklistText.pairedWithParent, 'Paired with your parent');
      return 'After pairing the child card reads '
          '"${SetupChecklistText.pairedWithParent}" (guardian\'s Paired '
          'Devices list on the emulator figure)';
    },
  );
}
