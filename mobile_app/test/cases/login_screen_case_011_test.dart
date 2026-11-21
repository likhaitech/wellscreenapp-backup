// CASE-011 - Authentication Module / Login Account
// Child enters valid credentials.
// Code being tested: lib/screens/login_screen.dart (loginUser)
// Firebase is replaced by a test double; the live run is on the emulator figure.
//
// Run: flutter test test/cases/login_screen_case_011_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_login_backend.dart';
import 'login_with_backend.dart';

void main() {
  testCase(
    'CASE-011',
    file: 'test/cases/login_screen_case_011_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description: 'Child enters valid credentials.',
    expected: 'Login successful; redirected to the child home screen.',
    body: (tester) async {
      final firebase = FakeLoginBackend(
        accounts: {'likhaitech+c1@gmail.com': 'Strong#Pass1'},
        roles: {'likhaitech+c1@gmail.com': 'child'},
      );
      final opened = await loginWith(tester, firebase,
          email: 'likhaitech+c1@gmail.com', password: 'Strong#Pass1');
      expect(firebase.signedInEmail, 'likhaitech+c1@gmail.com');
      expect(opened, 'child');
      return 'Login was successful and the system opened the child home '
          'screen';
    },
  );
}
