// CASE-163 - System Administration
// Run: flutter test test/cases/admin_users_screen_case_163_test.dart -r expanded

import 'package:app/screens/admin_users_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-163',
    file: 'test/cases/admin_users_screen_case_163_test.dart',
    codeTested: 'lib/screens/admin_users_screen.dart',
    description: 'Administrator sets a new password shorter than 6 characters.',
    expected: 'Password is not changed; “Password must be at least 6 characters.” is displayed.',
    body: (tester) async {
      final error = adminPasswordError('123');
      expect(error, 'Password must be at least 6 characters.');
      expect(adminPasswordError('Start#123'), isNull);
      return 'Password "123" is refused before anything is sent: "$error"';
    },
  );
}
