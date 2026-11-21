// CASE-001 - Authentication Module / Register Account
// User leaves the full name, email, or password field empty.
// Code being tested: lib/screens/register_screen.dart (registerUser)
//
// Run: flutter test test/cases/case_001_test.dart

import 'package:app/screens/register_screen.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

const _message = 'Please complete all required fields.';

/// Opens the real Register screen, fills only the given fields, taps
/// "Create account" and returns the message the screen shows.
Future<String> _submit(
  WidgetTester tester, {
  String name = '',
  String email = '',
  String password = '',
}) async {
  // A typical Android phone screen (411 x 914).
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1080 / 411;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
  await tester.pump();

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(3)); // Full name, Email address, Password
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);

  // Scroll down to "Create account" like a user would, then tap it.
  final button = find.byType(AppPillButton);
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pump(); // show the SnackBar
  await tester.pump(const Duration(milliseconds: 300));

  // Registration is blocked: still on the Register screen.
  expect(find.byType(RegisterScreen), findsOneWidget);
  expect(find.text(_message), findsOneWidget);
  return _message;
}

void main() {
  testCase(
    'CASE-001',
    description: 'User leaves the full name, email, or password field empty.',
    expected:
        'Registration is blocked and "Please complete all required fields." '
        'is displayed.',
    body: (tester) async {
      // All three empty, then each one empty on its own.
      await _submit(tester);
      await _submit(tester, email: 'juan@example.com', password: 'Strong#Pass1');
      await _submit(tester, name: 'Juan Dela Cruz', password: 'Strong#Pass1');
      final shown = await _submit(
        tester,
        name: 'Juan Dela Cruz',
        email: 'juan@example.com',
      );
      return 'Registration was blocked and the system displayed "$shown" '
          '(all fields empty; full name empty; email empty; password empty)';
    },
  );
}
