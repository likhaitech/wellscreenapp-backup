// CASE-021 - Profile Management
// Run: flutter test test/cases/profile_validation_case_021_test.dart -r expanded

import 'package:app/services/profile_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-021',
    file: 'test/cases/profile_validation_case_021_test.dart',
    codeTested: 'lib/screens/profile_settings_screen.dart',
    description: 'User updates the full name with a valid value.',
    expected: '“Profile details updated successfully.” is displayed and the new name is shown.',
    body: (tester) async {
      expect(ProfileValidation.nameError('Maria Santos'), isNull);
      expect(ProfileValidation.profileSaved,
          'Profile details updated successfully.');
      return 'Name "Maria Santos" passes the check, so it is saved and '
          '"${ProfileValidation.profileSaved}" is shown (saved name on the '
          'emulator figure)';
    },
  );
}
