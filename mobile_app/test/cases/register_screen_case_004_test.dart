// CASE-004 - Authentication Module / Register Account
// User registers with valid details and the Guardian role.
// Code being tested: lib/screens/register_screen.dart (registerUser)
//
// Firebase is replaced by a test double (FakeRegistrationBackend) that
// records what the real Register screen asks it to do. The live Firebase
// run is shown on the emulator figure.
//
// Run: flutter test test/cases/register_screen_case_004_test.dart -r expanded

import 'package:app/screens/register_screen.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_registration_backend.dart';

void main() {
  testCase(
    'CASE-004',
    file: 'test/cases/register_screen_case_004_test.dart',
    codeTested: 'lib/screens/register_screen.dart',
    description: 'User registers with valid details and the Guardian role.',
    expected:
        'Account is created, a verification link is sent to the email, and '
        'the Guardian Dashboard opens.',
    body: (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1080 / 411;
      addTearDown(tester.view.reset);

      final firebase = FakeRegistrationBackend();
      String? openedHomeFor;
      await tester.pumpWidget(MaterialApp(
        home: RegisterScreen(
          backend: firebase,
          openHome: (context, role) => openedHomeFor = role,
        ),
      ));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test Guardian One');
      await tester.enterText(fields.at(1), 'likhaitech+g1@gmail.com');
      await tester.enterText(fields.at(2), 'Strong#Pass1');
      // Guardian is the default role; tap it anyway like the user would.
      await tester.tap(find.text('Guardian'));
      await tester.pump();

      final button = find.byType(AppPillButton);
      await tester.scrollUntilVisible(button, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Account created with the typed details and the Guardian role.
      expect(firebase.createdEmail, 'likhaitech+g1@gmail.com');
      expect(firebase.createdPassword, 'Strong#Pass1');
      expect(firebase.savedProfile?['role'], 'parent');
      expect(firebase.savedProfile?['fullName'], 'Test Guardian One');
      expect(firebase.deleted, isFalse);
      // Verification link sent.
      expect(firebase.verificationSent, isTrue);
      expect(find.textContaining('Open the link sent to likhaitech+g1@gmail.com'),
          findsOneWidget);
      // Guardian Dashboard opened.
      expect(openedHomeFor, 'parent');

      return 'Account was created (role: guardian), a verification link was '
          'sent to likhaitech+g1@gmail.com, and the Guardian Dashboard opened';
    },
  );
}
