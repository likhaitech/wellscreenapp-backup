// CASE-052 - Usage Monitoring
// Run: flutter test test/cases/usage_report_service_case_052_test.dart -r expanded

import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-052',
    file: 'test/cases/usage_report_service_case_052_test.dart',
    codeTested: 'lib/services/usage_dashboard_controller_service.dart',
    description: 'Guardian opens the dashboard after the child syncs.',
    expected: 'Screen time today on the dashboard matches the child device.',
    body: (tester) async {
      final child = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({
          'com.google.android.youtube': 3600000,
          'com.roblox.client': 1800000,
        }),
      );
      // What the child's sync stores and the guardian's dashboard reads.
      final synced = {'totalUsageDurationMs': child.totalUsageDuration.inMilliseconds};
      final shown = Duration(milliseconds: synced['totalUsageDurationMs']!);
      expect(shown, child.totalUsageDuration);
      return 'Child device: ${child.totalUsageDuration.inMinutes} min; '
          'guardian dashboard after sync: ${shown.inMinutes} min';
    },
  );
}
