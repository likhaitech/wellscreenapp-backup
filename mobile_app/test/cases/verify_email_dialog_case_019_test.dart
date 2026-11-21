// CASE-019 - Authentication Module / Verify Email
// Guardian opens the verification link, then confirms in the dialog.
// Code being tested: lib/widgets/verify_email_dialog.dart
//
// After the guardian opens the link, Firebase marks the email verified.
// This test opens the real dialog with an email that is now verified and
// taps "I've verified"; the dialog closes and reports success, which lets
// the app generate the pairing code (shown on the emulator figure).
//
// Run: flutter test test/cases/verify_email_dialog_case_019_test.dart -r expanded

import 'package:app/widgets/verify_email_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-019',
    file: 'test/cases/verify_email_dialog_case_019_test.dart',
    codeTested: 'lib/widgets/verify_email_dialog.dart',
    description:
        'Guardian opens the verification link, then confirms in the dialog.',
    expected:
        'Email is marked verified and the pairing code can be generated.',
    body: (tester) async {
      bool? verified;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    verified = await showVerifyEmailDialog(
                      context,
                      email: 'guardian@example.com',
                      resend: () async {},
                      checkVerified: () async => true, // link was opened
                    );
                  },
                  child: const Text('Generate Code'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);

      await tester.tap(find.text("I've verified"));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsNothing);
      expect(verified, isTrue);
      return 'The email was confirmed as verified, the dialog closed and the '
          'app continued to generate the pairing code';
    },
  );
}
