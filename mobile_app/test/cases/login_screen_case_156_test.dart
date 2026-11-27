// CASE-156 - System Administration
// Run: flutter test test/cases/login_screen_case_156_test.dart -r expanded

import 'fake_login_backend.dart';
import 'login_with_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-156',
    file: 'test/cases/login_screen_case_156_test.dart',
    codeTested: 'lib/screens/admin_home_screen.dart',
    description: 'Administrator logs in with an administrator account.',
    expected: 'Login successful; the WellScreen Admin home opens with Users, Health, and Logs.',
    body: (tester) async {
      final backend = FakeLoginBackend(
        accounts: {'admin@wellscreen.app': 'Admin#2026'},
        roles: {'admin@wellscreen.app': 'admin'},
      );
      final opened = await loginWith(tester, backend,
          email: 'admin@wellscreen.app', password: 'Admin#2026');
      expect(opened, 'admin');
      return 'admin@wellscreen.app logged in on the real Login screen and the '
          'app opened the "$opened" home (WellScreen Admin: Users, Health, Logs)';
    },
  );
}
