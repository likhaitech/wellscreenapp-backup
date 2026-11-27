// CASE-054 - Usage Monitoring
// Run: flutter test test/cases/visible_apps_case_054_test.dart -r expanded

import 'package:app/services/visible_apps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-054',
    file: 'test/cases/visible_apps_case_054_test.dart',
    codeTested: 'lib/services/usage_dashboard_controller_service.dart',
    description: 'Guardian opens All Apps before the child syncs today.',
    expected: 'A message asks the guardian to have the child device sync usage.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 8, 0);
      final yesterday = DateTime(2026, 11, 21, 21, 30);
      expect(isUsageReportStale(yesterday, now), isTrue);
      expect(isUsageReportStale(DateTime(2026, 11, 22, 7, 55), now), isFalse);
      return 'The newest report is from yesterday, so All Apps shows '
          '"$syncUsageTodayMessage"';
    },
  );
}
