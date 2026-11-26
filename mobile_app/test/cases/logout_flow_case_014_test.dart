// CASE-014 - Authentication Module / Logout Account
// Guardian taps Sign Out from Settings and confirms in the dialog.
// Code being tested: lib/widgets/logout_flow.dart (used by the guardian's
// Settings Log out). Firebase sign-out is replaced by a test double.
//
// Run: flutter test test/cases/logout_flow_case_014_test.dart -r expanded

import 'package:app/screens/login_screen.dart';
import 'package:app/widgets/logout_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-014',
    file: 'test/cases/logout_flow_case_014_test.dart',
    codeTested: 'lib/widgets/logout_flow.dart',
    description: 'Guardian taps Sign Out from Settings and confirms.',
    expected:
        'A "Log out?" confirmation appears; after confirming, the guardian '
        'is signed out and the Login screen opens.',
    body: (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1080 / 411;
      addTearDown(tester.view.reset);

      var signedOut = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: Center(
              child: TextButton(
                onPressed: () async {
                  if (await confirmLogoutDialog(context)) {
                    if (!context.mounted) return;
                    await signOutToLogin(context,
                        signOut: () async => signedOut = true);
                  }
                },
                child: const Text('Log out'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsOneWidget);
      expect(signedOut, isFalse);

      await tester.tap(find.text('Logout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(signedOut, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      return 'The "Log out?" confirmation appeared; after tapping Logout the '
          'guardian was signed out and the Login screen opened';
    },
  );
}
