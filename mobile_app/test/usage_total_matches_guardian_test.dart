import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The child's screen-time total must match what the guardian sees
/// (ScreenTimeReportJobService.kt): WellScreen itself is left out and every
/// app counts, not only the top ten.
void main() {
  const min = 60000;
  final tracking = UsageTrackingService();
  final reports = UsageReportService();

  test('WellScreen itself is not counted as screen time', () {
    final apps = tracking.summarizeAllUsage({
      UsageTrackingService.ownPackage: 300 * min,
      'com.google.android.youtube': 45 * min,
    });
    expect(apps.map((a) => a.packageName),
        isNot(contains(UsageTrackingService.ownPackage)));
    final report = reports.generateFromSummaries(apps);
    expect(report.totalUsageDuration, const Duration(minutes: 45));
  });

  test('the total adds up every app, not only the top ten', () {
    final usage = {for (var i = 0; i < 12; i++) 'com.example.app$i': 10 * min};
    final report = reports.generateFromSummaries(
      tracking.summarizeAllUsage(usage),
    );
    expect(report.totalUsageDuration, const Duration(minutes: 120));
  });
}
