// CASE-023 - Profile Management
// Run: flutter test test/cases/profile_validation_case_023_test.dart -r expanded

import 'package:app/services/profile_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-023',
    file: 'test/cases/profile_validation_case_023_test.dart',
    codeTested: 'lib/screens/profile_settings_screen.dart',
    description: 'User enters a new password and a different confirmation.',
    expected: 'Password is not changed; “New password and confirmation do not match.” is displayed.',
    body: (tester) async {
      final error = ProfileValidation.passwordChangeError(
        current: 'OldPass#1',
        newPassword: 'NewPass#2',
        confirm: 'NewPass#3',
      );
      expect(error, 'New password and confirmation do not match.');
      return 'New "NewPass#2", confirm "NewPass#3": stopped with "$error"';
    },
  );
}
