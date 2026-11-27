// CASE-006 - Authentication Module / Login Account
// User taps Log in with the email or password field empty.
// Code being tested: lib/screens/login_screen.dart (loginUser)
//
// Run: flutter test test/cases/login_screen_case_006_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'login_steps.dart';

const _message = 'Please enter your email and password.';

void main() {
  testCase(
    'CASE-006',
    file: 'test/cases/login_screen_case_006_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description: 'User taps Log in with the email or password field empty.',
    expected: 'Login fails with "Please enter your email and password."',
    body: (tester) async {
      // Both empty, email empty, then password empty.
      for (final (email, password) in [
        ('', ''),
        ('', 'Strong#Pass1'),
        ('juan@example.com', ''),
      ]) {
        await submitLogin(tester, email: email, password: password);
        expect(find.text(_message), findsOneWidget);
        expect(stillOnLoginScreen(), isTrue);
      }
      return 'Login failed and the system displayed "$_message" (both '
          'fields empty; email empty; password empty)';
    },
  );
}
