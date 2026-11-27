// CASE-170 - System Administration
// Run: flutter test test/cases/admin_activity_widgets_case_170_test.dart -r expanded

import 'package:app/widgets/admin_activity_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-170',
    file: 'test/cases/admin_activity_widgets_case_170_test.dart',
    codeTested: 'lib/widgets/admin_activity_widgets.dart',
    description: 'Administrator checks the scheduled jobs (Monitoring check, Chat notifications).',
    expected: 'Each job shows when it last ran (for example “Last run just now”) or “Never ran”.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 10);
      final monitoring = AdminJobHealthCard.lastRunLabel(now.subtract(const Duration(seconds: 20)), now);
      final chat = AdminJobHealthCard.lastRunLabel(now.subtract(const Duration(minutes: 4)), now);
      final never = AdminJobHealthCard.lastRunLabel(null, now);
      expect(monitoring, 'Last run just now');
      expect(chat, 'Last run 4 min ago');
      expect(never, 'Never ran');
      return 'Monitoring check: "$monitoring"; Chat notifications: "$chat"; a '
          'job that never ran: "$never"';
    },
  );
}
