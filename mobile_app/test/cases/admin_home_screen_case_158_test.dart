// CASE-158 - System Administration
// Run: flutter test test/cases/admin_home_screen_case_158_test.dart -r expanded

import 'package:app/screens/admin_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-158',
    file: 'test/cases/admin_home_screen_case_158_test.dart',
    codeTested: 'lib/screens/admin_home_screen.dart',
    description: 'Administrator taps Sign out and confirms.',
    expected: 'A “Sign out?” confirmation appears; after confirming, the Login screen opens.',
    body: (tester) async {
      bool? confirmed;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => confirmed = await confirmAdminSignOut(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(confirmed, isTrue);
      return 'The "Sign out?" dialog appeared and confirming returned true, '
          'which signs out and opens the Login screen';
    },
  );
}
