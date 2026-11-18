import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects a digits-only password like 12345678', () {
      expect(PasswordPolicy.isStrong('12345678'), isFalse);
      expect(PasswordPolicy.missing('12345678'), [
        'An uppercase letter (A-Z)',
        'A lowercase letter (a-z)',
        'A special character (e.g. ! @ # \$ % ^ & *)',
      ]);
    });

    test('rejects passwords shorter than 8 characters', () {
      expect(PasswordPolicy.isStrong('Ab1!xyz'), isFalse);
      expect(
        PasswordPolicy.missing('Ab1!xyz'),
        ['At least 8 characters'],
      );
    });

    test('requires a special character', () {
      expect(PasswordPolicy.isStrong('Password1'), isFalse);
    });

    test('requires an uppercase letter', () {
      expect(PasswordPolicy.isStrong('password1!'), isFalse);
    });

    test('accepts a password meeting every rule', () {
      expect(PasswordPolicy.isStrong('Wellscreen@2026'), isTrue);
      expect(PasswordPolicy.isStrong('Abcdef1)'), isTrue);
      expect(PasswordPolicy.missing('Abcdef1)'), isEmpty);
    });

    test('a space does not count as a special character', () {
      expect(PasswordPolicy.isStrong('Abcdef1 x'), isFalse);
    });

    test('evaluate reports all five rules in order', () {
      final rules = PasswordPolicy.evaluate('');
      expect(rules, hasLength(5));
      expect(rules.every((rule) => !rule.met), isTrue);
    });
  });
}
