// CASE-134 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/report_export_service_case_134_test.dart -r expanded

import 'package:app/services/report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-134',
    file: 'test/cases/report_export_service_case_134_test.dart',
    codeTested: 'lib/services/report_export_service.dart',
    description: 'Guardian exports the child’s report.',
    expected: 'A PDF report of the child’s usage, risk level, and recommendations is created.',
    body: (tester) async {
      final data = <String, dynamic>{
        'name': 'Ana',
        'latestUsageReport': {
          'totalUsageDurationMs': 9000000,
          'patternStatus': 'warning',
          'recommendationMessage': 'Consider a break reminder.',
        },
        'mlRiskAssessment': {'label': 'Moderate Risk', 'confidence': 0.82},
      };
      final pdf = ReportExportService.buildReport(data, DateTime(2026, 11, 22, 9));
      final bytes = await tester.runAsync(() => pdf.save());
      expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
      return 'A ${(bytes.length / 1024).toStringAsFixed(1)} KB PDF was created '
          'with usage, risk level and recommendation for Ana';
    },
  );
}
