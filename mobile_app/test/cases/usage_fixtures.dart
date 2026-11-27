// Shared usage data for the pattern-detection test cases.

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';

AppUsageSummary app(String name, Duration used, {DateTime? lastUsed}) =>
    AppUsageSummary(
      packageName: 'com.example.${name.toLowerCase()}',
      displayName: name,
      usageDuration: used,
      lastTimeUsed: lastUsed,
    );

UsageReport quietReport() => UsageReport(
      totalUsageDuration: Duration.zero,
      topUsedApp: null,
      unhealthyAppCount: 0,
      generatedAt: DateTime(2026, 11, 22),
      patternStatus: UsagePatternStatus.healthy,
      recommendationMessage: '',
    );

List<String> typesOf(List<Map<String, Object>> events) =>
    [for (final e in events) e['type'] as String];
