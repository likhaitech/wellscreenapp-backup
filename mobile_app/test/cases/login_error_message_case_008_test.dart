// CASE-008 - Authentication Module / Login Account
// User enters a registered email with a wrong password.
// Code being tested: lib/services/login_error_message.dart, used by
// lib/screens/login_screen.dart when Firebase rejects the sign-in with
// "wrong-password".
//
// Note: if Firebase's email enumeration protection is on, Firebase
// answers "invalid-credential" instead and the app shows
// "Invalid email or password." - see the emulator figure.
//
// Run: flutter test test/cases/login_error_message_case_008_test.dart -r expanded

import 'package:app/services/login_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-008',
    file: 'test/cases/login_error_message_case_008_test.dart',
    codeTested: 'lib/services/login_error_message.dart',
    description: 'User enters a registered email with a wrong password.',
    expected: 'Login fails with "Incorrect password."',
    body: (tester) async {
      final shown = loginErrorMessage('wrong-password');
      expect(shown, 'Incorrect password.');
      return 'For Firebase\'s "wrong-password" answer (ambotsaemo333@gmail.com with the wrong password), login stopped and '
          'the system displayed "$shown"';
    },
  );
}
