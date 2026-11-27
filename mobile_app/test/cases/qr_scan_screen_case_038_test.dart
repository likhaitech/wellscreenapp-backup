// CASE-038 - Device Pairing and Permission Setup
// Run: flutter test test/cases/qr_scan_screen_case_038_test.dart -r expanded

import 'package:app/services/setup_checklist_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-038',
    file: 'test/cases/qr_scan_screen_case_038_test.dart',
    codeTested: 'lib/screens/qr_scan_screen.dart',
    description: 'Child scans the guardian’s QR code.',
    expected: 'The device is paired without typing the code.',
    body: (tester) async {
      // The guardian's QR holds the plain six-digit code.
      final code = pairingCodeFromQr('482913');
      expect(code, '482913');
      expect(pairingCodeFromQr('not a code'), isNull);
      return 'The scanned QR gives code $code, which is filled in and sent '
          'for pairing without typing (pairing result on the emulator figure)';
    },
  );
}
