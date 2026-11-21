// CASE-002 - Authentication Module / Register Account
// User enters a weak password such as 12345678.
// Code being tested: lib/services/password_policy.dart, shown by
// showPasswordRequirementsDialog (lib/widgets/wellscreen_ui.dart) from
// lib/screens/register_screen.dart.
//
// Run: flutter test test/cases/password_policy_case_002_test.dart

import 'package:app/services/password_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'register_steps.dart';

/// The ✓ / ✗ icon shown next to a rule in the dialog.
IconData _iconFor(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final icon = find.descendant(of: row.first, matching: find.byType(Icon));
  return tester.widget<Icon>(icon.first).icon!;
}

void main() {
  testCase(
    'CASE-002',
    file: 'test/cases/password_policy_case_002_test.dart',
    codeTested: 'lib/services/password_policy.dart',
    description: 'User enters a weak password such as 12345678.',
    expected:
        'Account is not created; the password requirements dialog lists the '
        'missing rules.',
    body: (tester) async {
      const weak = '12345678';

      // The rule itself: 12345678 is not a strong password.
      expect(PasswordPolicy.isStrong(weak), isFalse);
      final missing = PasswordPolicy.missing(weak);
      expect(missing, [
        'An uppercase letter (A-Z)',
        'A lowercase letter (a-z)',
        'A special character (e.g. ! @ # \$ % ^ & *)',
      ]);

      // On the real Register screen.
      await submitRegistration(
        tester,
        name: 'Juan Dela Cruz',
        email: 'juan@example.com',
        password: weak,
      );

      // The requirements dialog opens...
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Password is too weak'), findsOneWidget);

      // ...with a cross on every missing rule and a check on the met ones.
      for (final rule in missing) {
        expect(_iconFor(tester, rule), Icons.cancel_rounded, reason: rule);
      }
      expect(_iconFor(tester, 'At least 8 characters'),
          Icons.check_circle_rounded);
      expect(_iconFor(tester, 'A number (0-9)'), Icons.check_circle_rounded);

      // The account is not created: closing the dialog leaves the user on
      // the Register screen. (Registration stops before Firebase is called;
      // this test has no Firebase, so any attempt would have failed it.)
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // dialog closes
      expect(find.byType(AlertDialog), findsNothing);
      expect(stillOnRegisterScreen(), isTrue);

      return 'Account was not created; the system displayed "Password is too '
          'weak" listing the missing rules: ${missing.join('; ')} '
          '(8 characters and a number shown as met)';
    },
  );
}
