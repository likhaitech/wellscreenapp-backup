import 'package:app/widgets/phone_verification_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowPhoneVerificationHint', () {
    test('guardian without a verified number sees it', () {
      expect(
        shouldShowPhoneVerificationHint(role: 'parent', verifiedPhoneNumber: null),
        isTrue,
      );
      expect(
        shouldShowPhoneVerificationHint(role: 'parent', verifiedPhoneNumber: ' '),
        isTrue,
      );
    });

    test('hidden once verified', () {
      expect(
        shouldShowPhoneVerificationHint(
          role: 'parent',
          verifiedPhoneNumber: '+639171234567',
        ),
        isFalse,
      );
    });

    test('never shown to child or admin accounts', () {
      expect(
        shouldShowPhoneVerificationHint(role: 'child', verifiedPhoneNumber: null),
        isFalse,
      );
      expect(
        shouldShowPhoneVerificationHint(role: 'admin', verifiedPhoneNumber: null),
        isFalse,
      );
    });
  });

  testWidgets('hint shows the SMS backup message and is tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhoneVerificationHint(onTap: () => taps++)),
      ),
    );

    expect(find.text(PhoneVerificationHint.message), findsOneWidget);
    await tester.tap(find.byType(PhoneVerificationHint));
    expect(taps, 1);
  });
}
