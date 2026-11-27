import 'package:app/services/profile_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-022',
    file: 'test/cases/profile_validation_case_022_test.dart',
    codeTested: 'lib/screens/profile_settings_screen.dart',
    description: 'User enters a wrong current password.',
    expected: 'Password is not changed; “Current password is incorrect.” is displayed.',
    body: (tester) async {
      // Firebase answers a wrong current password with invalid-credential.
      final shown = ProfileValidation.passwordChangeFailure('invalid-credential');
      expect(shown, 'Current password is incorrect.');
      expect(ProfileValidation.passwordChangeFailure('wrong-password'), shown);
      return 'Firebase rejected the current password (invalid-credential), so '
          'the password is not changed and "$shown" is shown';
    },
  );
}
