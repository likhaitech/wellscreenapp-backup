// Shared steps for the Login Account test cases: open the REAL Login
// screen on a typical phone screen, type the email and password, scroll to
// "Log in" like a user would, and tap it.

import 'package:app/screens/login_screen.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> submitLogin(
  WidgetTester tester, {
  String email = '',
  String password = '',
}) async {
  // A typical Android phone screen (411 x 914).
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1080 / 411;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  await tester.pump();

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2)); // Email address, Password
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);

  final button = find.widgetWithText(AppPillButton, 'Log in');
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pump(); // show the message
  await tester.pump(const Duration(milliseconds: 300));
}

/// True when the user is still on the Login screen.
bool stillOnLoginScreen() =>
    find.byType(LoginScreen).evaluate().length == 1 &&
    find.text('Forgot password?').evaluate().isNotEmpty;
