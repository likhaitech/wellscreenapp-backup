import 'dart:io';

import 'package:app/services/daily_usage_history.dart';
import 'package:app/services/report_export_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const min = 60000;
  final now = DateTime(2026, 11, 28, 15);
  String key(int daysAgo) =>
      DailyUsageHistory.dayKey(DateTime(2026, 11, 28 - daysAgo));

  test('the PDF with a weekly summary is a valid PDF', () async {
    final data = <String, dynamic>{
      'name': 'Ana',
      'dailyGoalMinutes': 120,
      'dailyUsageTotals': {key(1): 150 * min, key(2): 60 * min, key(3): 90 * min},
      'usageReportUpdatedAt': Timestamp.fromDate(now),
      'latestUsageReport': {
        'totalUsageDurationMs': 45 * min,
        'patternStatus': 'healthy',
        'weeklyTopApps': [
          {'packageName': 'com.google.android.youtube', 'displayName': 'YouTube', 'usageDurationMs': 200 * min},
          {'packageName': 'com.roblox.client', 'displayName': 'Roblox', 'usageDurationMs': 100 * min},
        ],
        'weeklyAppsTotalMs': 345 * min,
      },
    };
    final bytes = await ReportExportService.buildReport(data, now).save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('today in the weekly totals comes from today\'s report', () {
    final data = <String, dynamic>{
      'dailyUsageTotals': {key(1): 30 * min},
      'usageReportUpdatedAt': Timestamp.fromDate(now),
      'latestUsageReport': {'totalUsageDurationMs': 45 * min},
    };
    final totals = ReportExportService.weeklyTotals(data, now);
    expect(totals[key(0)], 45 * min);
    expect(totals[key(1)], 30 * min);
  });

  test('an old report is not counted as today', () {
    final data = <String, dynamic>{
      'dailyUsageTotals': {key(1): 30 * min},
      'usageReportUpdatedAt': Timestamp.fromDate(DateTime(2026, 11, 27, 20)),
      'latestUsageReport': {'totalUsageDurationMs': 45 * min},
    };
    expect(ReportExportService.weeklyTotals(data, now)[key(0)], isNull);
  });

  test('the PDF can include the WellScreen logo', () async {
    final logo = File(ReportExportService.logoAsset).readAsBytesSync();
    final bytes = await ReportExportService.buildReport(
      {'name': 'Ana'},
      now,
      logo: logo,
    ).save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
