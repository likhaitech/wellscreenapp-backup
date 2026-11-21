// CASE-169 - System Administration
// Run: flutter test test/cases/admin_health_screen_case_169_test.dart -r expanded

import 'package:app/screens/admin_health_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-169',
    file: 'test/cases/admin_health_screen_case_169_test.dart',
    codeTested: 'lib/screens/admin_health_screen.dart',
    description: 'Administrator opens System health while the server is asleep or unreachable.',
    expected: '“Not reachable” and “The server may be waking up. Tap to try again.” are shown; the app does not crash.',
    body: (tester) async {
      final status = adminServerStatus(loading: false, hasOverview: false, failed: true);
      expect(status, 'Not reachable');
      expect(adminServerWakingMessage, 'The server may be waking up. Tap to try again.');
      return 'With no answer the card reads "$status" and '
          '"$adminServerWakingMessage" (tap to retry, no crash)';
    },
  );
}
