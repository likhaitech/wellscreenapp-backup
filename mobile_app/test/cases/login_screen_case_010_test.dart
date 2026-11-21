// CASE-010 - Authentication Module / Login Account
// Guardian enters valid credentials.
// Code being tested: lib/screens/login_screen.dart (loginUser)
// Firebase is replaced by a test double; the live run is on the emulator figure.
//
// Run: flutter test test/cases/login_screen_case_010_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_login_backend.dart';
import 'login_with_backend.dart';

void main() {
  testCase(
    'CASE-010',
    file: 'test/cases/login_screen_case_010_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description: 'Guardian enters valid credentials.',
    expected: 'Login successful; redirected to the Guardian Dashboard.',
    body: (tester) async {
      final firebase = FakeLoginBackend(
        accounts: {'ambotsaemo333@gmail.com': 'Strong#Pass1'},
        roles: {'ambotsaemo333@gmail.com': 'parent'},
      );
      final opened = await loginWith(tester, firebase,
          email: 'ambotsaemo333@gmail.com', password: 'Strong#Pass1');
      expect(firebase.signedInEmail, 'ambotsaemo333@gmail.com');
      expect(opened, 'parent');
      return 'Login was successful and the system opened the Guardian '
          'Dashboard';
    },
  );
}
