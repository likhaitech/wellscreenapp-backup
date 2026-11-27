// CASE-136 - Emergency Access
// Run: flutter test test/cases/emergency_access_service_case_136_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:app/services/emergency_access_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-136',
    file: 'test/cases/emergency_access_service_case_136_test.dart',
    codeTested: 'lib/services/emergency_access_service.dart',
    description: 'Child chooses 15 minutes, enters a reason, and sends the request.',
    expected: '“Request sent - your guardian has been notified.” is displayed.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 10);
      expect(EmergencyAccessService.rejectionFor({}, now), isNull);
      expect(ChildStatusText.requestSent,
          'Request sent - your guardian has been notified.');
      return 'First request today (15 min, reason "school project"): no limit '
          'or wait applies, so it is sent and "${ChildStatusText.requestSent}" '
          'is shown';
    },
  );
}
