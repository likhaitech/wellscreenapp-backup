// CASE-016 - Authentication Module / Reset Password
// User taps Forgot password? with a registered email.
// Code being tested: lib/screens/login_screen.dart (resetPassword)
// Firebase is replaced by a test double; the real email is shown on the
// emulator figure.
//
// Run: flutter test test/cases/login_screen_case_016_test.dart -r expanded

import 'package:app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_login_backend.dart';

void main() {
  testCase(
    'CASE-016',
    file: 'test/cases/login_screen_case_016_test.dart',
    codeTested: 'lib/screens/login_screen.dart',
    description: 'User taps Forgot password? with a registered email.',
    expected:
        'A password reset link is sent and a confirmation message is '
        'displayed.',
    body: (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1080 / 411;
      addTearDown(tester.view.reset);

      final firebase = FakeLoginBackend(
        accounts: {'likhaitech+g1@gmail.com': 'Strong#Pass1'},
      );
      await tester.pumpWidget(
          MaterialApp(home: LoginScreen(backend: firebase)));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField).at(0), 'likhaitech+g1@gmail.com');

      final link = find.text('Forgot password?');
      await tester.scrollUntilVisible(link, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(firebase.resetSentTo, 'likhaitech+g1@gmail.com');
      expect(find.textContaining('a password reset link has been sent'),
          findsOneWidget);
      return 'A password reset link was sent to likhaitech+g1@gmail.com and '
          'the system displayed the confirmation message';
    },
  );
}
