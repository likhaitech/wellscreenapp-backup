// CASE-048 - Usage Monitoring
// Run: flutter test test/cases/usage_tracking_service_case_048_test.dart -r expanded

import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-048',
    file: 'test/cases/usage_tracking_service_case_048_test.dart',
    codeTested: 'lib/services/usage_tracking_service.dart',
    description: 'Child uses several apps.',
    expected: 'Screen time today on the child home screen increases with the usage.',
    body: (tester) async {
      final tracking = UsageTrackingService();
      final reports = UsageReportService();
      const min = 60000;
      final morning = reports.generateFromSummaries(tracking.summarizeUsage({
        'com.google.android.youtube': 20 * min,
      }));
      final afternoon = reports.generateFromSummaries(tracking.summarizeUsage({
        'com.google.android.youtube': 35 * min,
        'com.zhiliaoapp.musically': 25 * min,
        'com.roblox.client': 15 * min,
      }));
      expect(morning.totalUsageDuration.inMinutes, 20);
      expect(afternoon.totalUsageDuration.inMinutes, 75);
      return 'Screen time today went from ${morning.totalUsageDuration.inMinutes} '
          'min (YouTube only) to ${afternoon.totalUsageDuration.inMinutes} min '
          'after using YouTube, TikTok and Roblox';
    },
  );
}
