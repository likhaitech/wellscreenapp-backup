// CASE-015 - Authentication Module / Reset Password
// User taps Forgot password? with the email field empty.
// Code being tested: lib/screens/login_screen.dart (resetPassword)
//
// Run: flutter test test/cases/login_screen_case_015_test.dart -r expanded

import 'package:app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

const _message = 'Enter your email above, then tap Forgot password.';

void main() {
  testCase(
    'CASE-015',
    file: 'test/cases/login_screen_case_015_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description: 'User taps Forgot password? with the email field empty.',
    expected: 'No email is sent; "$_message" is displayed.',
    body: (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1080 / 411;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      final link = find.text('Forgot password?');
      await tester.scrollUntilVisible(
        link,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The message shows, and no email is sent: the screen stops before
      // calling Firebase (this test has no Firebase, so a send attempt
      // would have failed it).
      expect(find.text(_message), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      return 'No reset email was sent and the system displayed "$_message"';
    },
  );
}
