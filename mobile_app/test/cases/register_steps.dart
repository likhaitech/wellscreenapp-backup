// Shared steps for the Register Account test cases: open the REAL
// Register screen on a typical phone screen, fill in the fields, scroll to
// "Create account" like a user would, and tap it.

import 'package:app/screens/register_screen.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> submitRegistration(
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

  final button = find.byType(AppPillButton);
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pump(); // show the message or dialog
  await tester.pump(const Duration(milliseconds: 300));
}

/// True when the user is still on the Register screen (nothing was created
/// and no other screen opened).
bool stillOnRegisterScreen() =>
    find.byType(RegisterScreen).evaluate().length == 1 &&
    find.text('Already have an account?').evaluate().isNotEmpty;
