import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/pairing_api_service.dart';
import 'package:app/widgets/verify_email_dialog.dart';

void main() {
  group('runWithEmailVerification', () {
    testWidgets('returns the result when pairing succeeds', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final result = await runWithEmailVerification(ctx, () async => 42);
      expect(result, 42);
    });

    testWidgets('passes other errors through unchanged', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await expectLater(
        runWithEmailVerification<int>(
          ctx,
          () async => throw Exception('Invalid pairing code.'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid pairing code.'),
          ),
        ),
      );
    });
  });

  test('EmailNotVerifiedException shows the server message', () {
    const error = EmailNotVerifiedException('Verify your email first.');
    expect(error.toString(), 'Verify your email first.');
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
