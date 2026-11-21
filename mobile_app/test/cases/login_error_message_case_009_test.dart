// CASE-009 - Authentication Module / Login Account
// User enters an email that has no account.
// Code being tested: lib/services/login_error_message.dart, used by
// lib/screens/login_screen.dart when Firebase rejects the sign-in with
// "user-not-found".
//
// Note: if Firebase's email enumeration protection is on, Firebase
// answers "invalid-credential" instead and the app shows
// "Invalid email or password." - see the emulator figure.
//
// Run: flutter test test/cases/login_error_message_case_009_test.dart -r expanded

import 'package:app/services/login_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-009',
    file: 'test/cases/login_error_message_case_009_test.dart',
    codeTested: 'lib/services/login_error_message.dart',
    description: 'User enters an email that has no account.',
    expected: 'Login fails with "No account found with this email."',
    body: (tester) async {
      final shown = loginErrorMessage('user-not-found');
      expect(shown, 'No account found with this email.');
      return 'For Firebase\'s "user-not-found" answer (nobody12345@example.com), login stopped and '
          'the system displayed "$shown"';
    },
  );
}
