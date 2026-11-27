// CASE-024 - Profile Management
// Run: flutter test test/cases/profile_validation_case_024_test.dart -r expanded

import 'package:app/services/profile_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-024',
    file: 'test/cases/profile_validation_case_024_test.dart',
    codeTested: 'lib/screens/profile_settings_screen.dart',
    description: 'User enters a new password that is the same as the current one.',
    expected: 'Password is not changed; “New password must be different from the current one.” is displayed.',
    body: (tester) async {
      final error = ProfileValidation.passwordChangeError(
        current: 'SamePass#1',
        newPassword: 'SamePass#1',
        confirm: 'SamePass#1',
      );
      expect(error, 'New password must be different from the current one.');
      return 'New password equal to the current one: stopped with "$error"';
    },
  );
}
