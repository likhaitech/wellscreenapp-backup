// CASE-017 - Authentication Module / Reset Password
// User sets a new password from the reset link and logs in with it.
// Code being tested: lib/screens/login_screen.dart (loginUser)
// Setting the new password happens on Firebase's reset page (emulator
// figure). This test logs in with the old and the new password against a
// Firebase test double that holds the new password.
//
// Run: flutter test test/cases/login_screen_case_017_test.dart -r expanded

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_login_backend.dart';
import 'login_with_backend.dart';

void main() {
  testCase(
    'CASE-017',
    file: 'test/cases/login_screen_case_017_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description:
        'User sets a new password from the reset link and logs in with it.',
    expected: 'Login with the new password is successful.',
    body: (tester) async {
      // The account after the reset: only the new password works.
      FakeLoginBackend afterReset() => FakeLoginBackend(
            accounts: {'likhaitech+g1@gmail.com': 'NewStrong#Pass2'},
            roles: {'likhaitech+g1@gmail.com': 'parent'},
          );

      final old = await loginWith(tester, afterReset(),
          email: 'likhaitech+g1@gmail.com', password: 'Strong#Pass1');
      expect(old, isNull);
      expect(find.text('Incorrect password.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // close the old screen
      final firebase = afterReset();
      final opened = await loginWith(tester, firebase,
          email: 'likhaitech+g1@gmail.com', password: 'NewStrong#Pass2');
      expect(firebase.signedInEmail, 'likhaitech+g1@gmail.com');
      expect(opened, 'parent');
      return 'The old password was refused and login with the new password '
          'was successful (Guardian Dashboard opened)';
    },
  );
}
