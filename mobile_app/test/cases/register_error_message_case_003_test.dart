// CASE-003 - Authentication Module / Register Account
// User registers with an email address that is already in use.
// Code being tested: lib/services/register_error_message.dart, used by
// lib/screens/register_screen.dart when Firebase refuses the new account.
//
// Firebase itself decides that an email is taken (it answers with the
// error code "email-already-in-use"); this test checks what WellScreen
// does with that answer. The full flow is shown on the emulator figure.
//
// Run: flutter test test/cases/register_error_message_case_003_test.dart -r expanded

import 'package:app/services/register_error_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-003',
    file: 'test/cases/register_error_message_case_003_test.dart',
    codeTested: 'lib/services/register_error_message.dart',
    description: 'User registers with an email address that is already in use.',
    expected:
        'Registration is blocked and an "email already in use" message is '
        'displayed.',
    body: (tester) async {
      // The exact answer Firebase gives for a taken email.
      final firebaseAnswer = FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );

      final shown = registerErrorMessage(firebaseAnswer);

      expect(shown.toLowerCase(), contains('already in use'));
      expect(shown, 'This email is already in use. Log in instead, or use a '
          'different email.');

      return 'For Firebase\'s "email-already-in-use" answer, registration '
          'stopped and the system displayed "$shown"';
    },
  );
}
