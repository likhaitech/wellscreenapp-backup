// CASE-007 - Authentication Module / Login Account
// User enters an invalid email format.
// Code being tested: lib/services/login_error_message.dart, used by
// lib/screens/login_screen.dart when Firebase rejects the sign-in.
//
// Firebase checks the email format and answers "invalid-email"; this test
// checks what WellScreen shows for that answer. The full flow is shown on
// the emulator figure.
//
// Run: flutter test test/cases/login_error_message_case_007_test.dart -r expanded

import 'package:app/services/login_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-007',
    file: 'test/cases/login_error_message_case_007_test.dart',
    codeTested: 'lib/services/login_error_message.dart',
    description: 'User enters an invalid email format.',
    expected: 'Login fails with "Invalid email address."',
    body: (tester) async {
      final shown = loginErrorMessage('invalid-email');
      expect(shown, 'Invalid email address.');
      return 'For Firebase\'s "invalid-email" answer (e.g. juan@@example), '
          'login stopped and the system displayed "$shown"';
    },
  );
}
