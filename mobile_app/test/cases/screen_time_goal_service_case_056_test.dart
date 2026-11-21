// CASE-056 - Usage Monitoring
// Run: flutter test test/cases/screen_time_goal_service_case_056_test.dart -r expanded

import 'package:app/services/screen_time_goal_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-056',
    file: 'test/cases/screen_time_goal_service_case_056_test.dart',
    codeTested: 'lib/services/screen_time_goal_service.dart',
    description: 'Child opens the home screen.',
    expected: 'The child sees screen time today and the daily goal.',
    body: (tester) async {
      final report = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({'com.google.android.youtube': 5400000}),
      );
      final result = ScreenTimeGoalService().evaluate(
        report: report,
        dailyLimit: const Duration(hours: 2),
      );
      expect(result.usedDuration.inMinutes, 90);
      expect(result.remainingDuration.inMinutes, 30);
      return 'Home screen: ${result.usedDuration.inMinutes} min today of a '
          '2h goal (${(result.progressPercent * 100).round()}%, '
          '${result.remainingDuration.inMinutes} min left)';
    },
  );
}
