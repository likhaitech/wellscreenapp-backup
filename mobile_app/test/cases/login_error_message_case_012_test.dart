// CASE-012 - Authentication Module / Login Account
// User logs in to an account that was deactivated.
// Code being tested: lib/services/login_error_message.dart, used by
// lib/screens/login_screen.dart. When the admin deactivates an account,
// Firebase refuses its sign-in with "user-disabled".
//
// Run: flutter test test/cases/login_error_message_case_012_test.dart -r expanded

import 'package:app/services/login_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-012',
    file: 'test/cases/login_error_message_case_012_test.dart',
    codeTested: 'lib/services/login_error_message.dart',
    description: 'User logs in to an account that was deactivated.',
    expected: 'Login fails with "This account has been disabled."',
    body: (tester) async {
      final shown = loginErrorMessage('user-disabled');
      expect(shown, 'This account has been disabled.');
      return 'For Firebase\'s "user-disabled" answer (account deactivated by '
          'the admin), login stopped and the system displayed "$shown"';
    },
  );
}
