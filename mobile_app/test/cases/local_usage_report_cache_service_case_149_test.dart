// CASE-149 - Offline Logging and Synchronization
// Run: flutter test test/cases/local_usage_report_cache_service_case_149_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:app/services/local_usage_report_cache_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-149',
    file: 'test/cases/local_usage_report_cache_service_case_149_test.dart',
    codeTested: 'lib/services/local_usage_report_cache_service.dart',
    description: 'Child uses apps while the phone has no internet.',
    expected: 'Usage is saved on the phone and “Offline - will sync when reconnected” is shown.',
    body: (tester) async {
      SharedPreferences.setMockInitialValues({});
      final report = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({'com.roblox.client': 2400000}),
      );
      final cache = LocalUsageReportCacheService();
      await cache.saveTodayReport(report);
      final saved = await cache.getCachedTodayReport();
      expect(saved?.totalUsageDuration, report.totalUsageDuration);
      final line = ChildStatusText.syncIndicator(
        isOnline: false, lastOutcome: null, autoSyncMinutes: 5);
      expect(line, 'Offline - will sync when reconnected');
      return '${saved!.totalUsageDuration.inMinutes} min of usage saved on the '
          'phone while offline; the status reads "$line"';
    },
  );
}
