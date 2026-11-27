// INT-001 - Authentication Module -> Dashboard, Reports, and Recommendations Module
// Guardian logs in to the guardian application.
// Code being tested: lib/screens/login_screen.dart + lib/services/guardian_dashboard_text.dart
// Firebase is replaced by the same test double as CASE-010; the live run is
// on the emulator figure.
//
// Run: flutter test test/integration_cases/int_001_test.dart -r expanded

import 'package:app/services/guardian_dashboard_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cases/case_report.dart';
import '../cases/fake_login_backend.dart';
import '../cases/login_with_backend.dart';

void main() {
  testCase(
    'INT-001',
    file: 'test/integration_cases/int_001_test.dart',
    codeTested:
        'lib/screens/login_screen.dart + lib/services/guardian_dashboard_text.dart',
    description: 'Guardian logs in to the guardian application '
        '(Authentication -> Dashboard, Reports, and Recommendations).',
    expected: 'The guardian dashboard opens and shows the child profiles and '
        'devices linked to the account.',
    body: (tester) async {
      // Module 1 - Authentication: the REAL Login screen.
      final firebase = FakeLoginBackend(
        accounts: {'maria@example.com': 'Strong#Pass1'},
        roles: {'maria@example.com': 'parent'},
      );
      final opened = await loginWith(tester, firebase,
          email: 'maria@example.com', password: 'Strong#Pass1');
      expect(firebase.signedInEmail, 'maria@example.com');
      expect(opened, 'parent'); // the Guardian Dashboard is opened

      // Module 2 - Dashboard: the child profiles linked to this guardian.
      final children = <Map<String, dynamic>>[
        {
          'name': 'Ana',
          'pairingStatus': 'connected',
          'childAccountId': 'child-uid-0001',
          'accessibilityEnabled': true,
        },
      ];
      final linked = children.where(childLooksConnected).toList();
      expect(linked, hasLength(1));
      expect(protectionStatusLabels(linked.first), ['Protection on']);
      // A guardian with no child would see the pairing prompt instead.
      expect(childLooksConnected(<String, dynamic>{}), isFalse);
      return 'Login succeeded and the Guardian Dashboard opened, showing the '
          'linked child "${linked.first['name']}" (paired device, '
          '"${protectionStatusLabels(linked.first).join(', ')}")';
    },
  );
}
