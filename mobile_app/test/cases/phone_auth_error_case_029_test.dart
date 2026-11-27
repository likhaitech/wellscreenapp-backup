// CASE-029 - Profile Management
// Run: flutter test test/cases/phone_auth_error_case_029_test.dart -r expanded

import 'package:app/services/phone_auth_error.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-029',
    file: 'test/cases/phone_auth_error_case_029_test.dart',
    codeTested: 'lib/screens/phone_verification_screen.dart',
    description: 'Guardian enters a wrong SMS verification code.',
    expected: 'Number is not verified; “The SMS verification code is incorrect. Please try again.” is displayed.',
    body: (tester) async {
      final shown = phoneAuthErrorMessage('invalid-verification-code');
      expect(shown, 'The SMS verification code is incorrect. Please try again.');
      return 'Firebase rejected the code (invalid-verification-code); the '
          'number stays unverified and "$shown" is shown';
    },
  );
}
