// CASE-018 - Authentication Module / Verify Email
// Guardian with an unverified email taps Generate Code.
// Code being tested: lib/widgets/verify_email_dialog.dart
//
// The server refuses to create a pairing code for an unverified email
// (EmailNotVerifiedException); the app then shows the "Verify your email"
// dialog. This test opens that real dialog with an email that is still
// unverified.
//
// Run: flutter test test/cases/verify_email_dialog_case_018_test.dart -r expanded

import 'package:app/services/pairing_api_service.dart';
import 'package:app/widgets/verify_email_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-018',
    file: 'test/cases/verify_email_dialog_case_018_test.dart',
    codeTested: 'lib/widgets/verify_email_dialog.dart',
    description: 'Guardian with an unverified email taps Generate Code.',
    expected:
        'No pairing code is created; the "Verify your email" dialog is '
        'displayed.',
    body: (tester) async {
      // The server's refusal carries its message to the app.
      const refusal = EmailNotVerifiedException('Verify your email first.');
      expect(refusal.toString(), 'Verify your email first.');

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
                      checkVerified: () async => false, // still unverified
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

      // Tapping "I've verified" before verifying keeps the dialog open.
      await tester.tap(find.text("I've verified"));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('Not verified yet'), findsOneWidget);

      // Closing it gives no verification, so no code is generated.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(verified, isFalse);

      return 'No pairing code was created; the system displayed the "Verify '
          'your email" dialog (and "Not verified yet" when tapping I\'ve '
          'verified too early)';
    },
  );
}
