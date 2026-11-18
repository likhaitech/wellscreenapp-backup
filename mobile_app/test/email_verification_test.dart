import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/email_verification_policy.dart';
import 'package:app/widgets/verify_email_dialog.dart';

void main() {
  group('EmailVerificationPolicy.mustVerify', () {
    final cutoff = DateTime.utc(2026, 11, 18, 10);

    test('new unverified account must verify', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: false,
          accountCreatedAt: DateTime.utc(2026, 11, 20),
          cutoff: cutoff,
        ),
        isTrue,
      );
    });

    test('account created exactly at the cutoff must verify', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: false,
          accountCreatedAt: cutoff,
          cutoff: cutoff,
        ),
        isTrue,
      );
    });

    test('account created before the cutoff keeps working', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: false,
          accountCreatedAt: DateTime.utc(2026, 11, 14),
          cutoff: cutoff,
        ),
        isFalse,
      );
    });

    test('verified account is never asked', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: true,
          isAdmin: false,
          accountCreatedAt: DateTime.utc(2026, 12, 1),
          cutoff: cutoff,
        ),
        isFalse,
      );
    });

    test('admin is never blocked', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: true,
          accountCreatedAt: DateTime.utc(2026, 12, 1),
          cutoff: cutoff,
        ),
        isFalse,
      );
    });

    test('unknown creation time asks for verification', () {
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: false,
          accountCreatedAt: null,
          cutoff: cutoff,
        ),
        isTrue,
      );
    });

    test('local-time creation dates are compared in UTC', () {
      // 18 Nov 2026 5:59 PM in Manila (UTC+8) is before 6:00 PM.
      final beforeInManila = DateTime.utc(2026, 11, 18, 9, 59).toLocal();
      expect(
        EmailVerificationPolicy.mustVerify(
          emailVerified: false,
          isAdmin: false,
          accountCreatedAt: beforeInManila,
          cutoff: cutoff,
        ),
        isFalse,
      );
    });
  });

  group('showVerifyEmailDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required Future<bool> Function() checkVerified,
      Future<void> Function()? resend,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    showVerifyEmailDialog(
                      context,
                      email: 'kid@example.com',
                      resend: resend ?? () async {},
                      checkVerified: checkVerified,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
    }

    testWidgets('returns true once the email is verified', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showVerifyEmailDialog(
                  context,
                  email: 'kid@example.com',
                  resend: () async {},
                  checkVerified: () async => true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I've verified"));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('stays open with a message when not verified yet',
        (tester) async {
      await openDialog(tester, checkVerified: () async => false);
      await tester.tap(find.text("I've verified"));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('Not verified yet'), findsOneWidget);
    });

    testWidgets('Resend calls the resend callback', (tester) async {
      var resent = 0;
      await openDialog(
        tester,
        checkVerified: () async => false,
        resend: () async => resent++,
      );
      await tester.tap(find.text('Resend link'));
      await tester.pumpAndSettle();
      expect(resent, 1);
      expect(find.textContaining('A new link was sent'), findsOneWidget);
    });

    testWidgets('Cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showVerifyEmailDialog(
                  context,
                  email: 'kid@example.com',
                  resend: () async {},
                  checkVerified: () async => true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
