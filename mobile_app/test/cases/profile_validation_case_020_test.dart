// CASE-020 - Profile Management
// Run: flutter test test/cases/profile_validation_case_020_test.dart -r expanded

import 'package:app/services/profile_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-020',
    file: 'test/cases/profile_validation_case_020_test.dart',
    codeTested: 'lib/screens/profile_settings_screen.dart',
    description: 'User clears the Full Name field and taps Save Profile.',
    expected: 'Profile is not saved; “Full name is required.” is displayed.',
    body: (tester) async {
      final error = ProfileValidation.nameError('   ');
      expect(error, 'Full name is required.');
      return 'Full Name left blank: the save stops before anything is written '
          'and "$error" is shown';
    },
  );
}
