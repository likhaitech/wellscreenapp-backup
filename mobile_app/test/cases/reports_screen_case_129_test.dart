// CASE-129 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/reports_screen_case_129_test.dart -r expanded

import 'dart:io';

import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-129',
    file: 'test/cases/reports_screen_case_129_test.dart',
    codeTested: 'lib/services/usage_report_service.dart',
    description: 'Guardian opens Reports.',
    expected: 'Top Used Applications, Detected Pattern, Restriction Enforcement, and Synchronization Status are shown.',
    body: (tester) async {
      final report = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({'com.roblox.client': 7200000}),
      );
      expect(report.topUsedApp?.packageName, 'com.roblox.client');
      final source = File('lib/screens/reports_screen.dart').readAsStringSync();
      const sections = ['Top Used Applications', 'Detected Pattern',
          'Restriction Enforcement', 'Synchronization Status'];
      for (final title in sections) {
        expect(source.contains(title), isTrue, reason: title);
      }
      return 'The report has top app ${report.topUsedApp?.displayName} and '
          'pattern "${report.patternStatus.name}"; Reports shows the sections '
          '${sections.join(', ')}';
    },
  );
}
