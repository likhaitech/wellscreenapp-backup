// CASE-161 - System Administration
// Run: flutter test test/cases/admin_users_screen_case_161_test.dart -r expanded

import 'package:app/screens/admin_users_screen.dart';
import 'package:app/services/admin_users_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-161',
    file: 'test/cases/admin_users_screen_case_161_test.dart',
    codeTested: 'lib/screens/admin_users_screen.dart',
    description: 'Administrator searches for an email or picks the Deactivated filter.',
    expected: 'Only matching accounts are shown; “No users found” is shown when nothing matches.',
    body: (tester) async {
      const users = [
        AdminManagedUser(uid: 'p1', email: 'maria@example.com', displayName: 'Maria', role: 'parent', disabled: false),
        AdminManagedUser(uid: 'c1', email: 'ana@example.com', displayName: 'Ana', role: 'child', disabled: true),
        AdminManagedUser(uid: 'c2', email: 'ben@example.com', displayName: 'Ben', role: 'child', disabled: false),
      ];
      final search = filterAdminUsers(users, 'maria', AdminUserFilter.all);
      final off = filterAdminUsers(users, '', AdminUserFilter.deactivated);
      final none = filterAdminUsers(users, 'nobody@x.com', AdminUserFilter.all);
      expect(search.map((u) => u.email), ['maria@example.com']);
      expect(off.map((u) => u.email), ['ana@example.com']);
      expect(none, isEmpty);
      return 'Search "maria" -> maria@example.com; Deactivated -> '
          'ana@example.com; a made-up email -> no accounts ("No users found")';
    },
  );
}
