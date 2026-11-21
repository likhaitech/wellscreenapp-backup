// CASE-155 - Offline Logging and Synchronization
// Run: flutter test test/cases/report_export_service_case_155_test.dart -r expanded

import 'package:app/services/report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-155',
    file: 'test/cases/report_export_service_case_155_test.dart',
    codeTested: 'lib/services/sync_status_service.dart',
    description: 'Guardian opens Synchronization Status in Reports.',
    expected: 'Recent sync attempts and their results are listed.',
    body: (tester) async {
      final log = ReportExportService.decodeLog([
        {'outcome': 'failed', 'timestampMs': 1000},
        'not an entry',
        {'outcome': 'synced', 'timestampMs': 2000},
      ]);
      expect(log.map((e) => e['outcome']), ['failed', 'synced']);
      return 'Synchronization Status lists ${log.length} attempts in order: '
          '${log.map((e) => e['outcome']).join(', ')}';
    },
  );
}
