// CASE-044 - Device Pairing and Permission Setup
// Run: flutter test test/cases/setup_checklist_text_case_044_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-044',
    file: 'test/cases/setup_checklist_text_case_044_test.dart',
    codeTested: 'mobile_app/android/app/src/main/kotlin/com/wellscreen/app/WellScreenDeviceAdminReceiver.kt',
    description: 'Child activates WellScreen as Device Administrator.',
    expected: 'The checklist shows that WellScreen cannot be uninstalled without turning protection off.',
    body: (tester) async {
      final shown = SetupChecklistText.uninstallProtection(true);
      expect(shown, contains('cannot be uninstalled without turning this off'));
      return 'With Device Administrator on the checklist row reads "$shown"';
    },
  );
}
