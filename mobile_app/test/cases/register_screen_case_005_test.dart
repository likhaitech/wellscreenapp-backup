// CASE-005 - Authentication Module / Register Account
// User registers with valid details and the Child role.
// Code being tested: lib/screens/register_screen.dart (registerUser)
//
// Firebase is replaced by a test double (FakeRegistrationBackend) that
// records what the real Register screen asks it to do. The live Firebase
// run is shown on the emulator figure.
//
// Run: flutter test test/cases/register_screen_case_005_test.dart -r expanded

import 'package:app/screens/register_screen.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'fake_registration_backend.dart';

void main() {
  testCase(
    'CASE-005',
    file: 'test/cases/register_screen_case_005_test.dart',
    codeTested: 'lib/screens/register_screen.dart',
    description: 'User registers with valid details and the Child role.',
    expected:
        'Account is created and the child home screen opens with "Not paired '
        'yet".',
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
      await tester.enterText(fields.at(0), 'Test Child One');
      await tester.enterText(fields.at(1), 'likhaitech+c1@gmail.com');
      await tester.enterText(fields.at(2), 'Strong#Pass1');
      // Pick the Child role.
      await tester.tap(find.text('Child'));
      await tester.pump();

      final button = find.byType(AppPillButton);
      await tester.scrollUntilVisible(button, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Account created with the typed details and the Child role.
      expect(firebase.createdEmail, 'likhaitech+c1@gmail.com');
      expect(firebase.savedProfile?['role'], 'child');
      expect(firebase.savedProfile?['fullName'], 'Test Child One');
      // Saved as not paired yet - the child home screen shows this as
      // "Not paired yet".
      expect(firebase.savedProfile?['pairingStatus'], 'not_paired');
      expect(firebase.savedProfile?['pairedParentId'], isNull);
      expect(firebase.deleted, isFalse);
      // Child home screen opened.
      expect(openedHomeFor, 'child');

      return 'Account was created (role: child, pairing status: not paired) '
          'and the child home screen opened';
    },
  );
}
