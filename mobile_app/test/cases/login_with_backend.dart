// Opens the REAL Login screen with a Firebase test double, types the
// email and password, and taps "Log in". Returns the role whose home
// screen the app opened (or null if none opened).

import 'package:app/screens/login_screen.dart';
import 'package:app/services/login_backend.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String?> loginWith(
  WidgetTester tester,
  LoginBackend backend, {
  required String email,
  required String password,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1080 / 411;
  addTearDown(tester.view.reset);

  String? opened;
  await tester.pumpWidget(MaterialApp(
    home: LoginScreen(
      backend: backend,
      openHome: (context, role) => opened = role,
    ),
  ));
  await tester.pump();

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);

  final button = find.widgetWithText(AppPillButton, 'Log in');
  await tester.scrollUntilVisible(button, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return opened;
}
