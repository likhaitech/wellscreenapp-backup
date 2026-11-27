// CASE-172 - System Administration
// Run: flutter test test/cases/admin_logs_screen_case_172_test.dart -r expanded

import 'package:app/screens/admin_logs_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-172',
    file: 'test/cases/admin_logs_screen_case_172_test.dart',
    codeTested: 'lib/screens/admin_logs_screen.dart',
    description: 'Administrator searches the logs or picks the Error, Warning, or Activity filter.',
    expected: 'Only matching log entries are shown; “No matching logs” is shown when nothing matches.',
    body: (tester) async {
      final logs = <Map<String, dynamic>>[
        {'level': 'error', 'action': 'monitoring_sweep', 'message': 'Sweep failed'},
        {'level': 'info', 'action': 'user_deactivated', 'message': 'Deactivated ana@example.com'},
        {'level': 'warning', 'action': 'push_failed', 'message': 'Push not delivered'},
      ];
      List<String?> pick(AdminLogFilter f, String q) =>
          [for (final l in logs) if (adminLogMatches(l, f, q)) l['message'] as String?];
      expect(pick(AdminLogFilter.errors, ''), ['Sweep failed']);
      expect(pick(AdminLogFilter.activity, ''), ['Deactivated ana@example.com']);
      expect(pick(AdminLogFilter.all, 'ana@'), ['Deactivated ana@example.com']);
      expect(pick(AdminLogFilter.all, 'zzz'), isEmpty);
      return 'Error -> "Sweep failed"; Activity -> "Deactivated ana@example.com"; '
          'search "ana@" finds it; search "zzz" finds nothing ("No matching logs")';
    },
  );
}
