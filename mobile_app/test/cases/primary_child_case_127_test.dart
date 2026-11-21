// CASE-127 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/primary_child_case_127_test.dart -r expanded

import 'package:app/services/guardian_dashboard_text.dart';
import 'package:app/utils/primary_child.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-127',
    file: 'test/cases/primary_child_case_127_test.dart',
    codeTested: 'lib/utils/primary_child.dart',
    description: 'Guardian with two child records opens the app after one child used the phone.',
    expected: 'The dashboard opens the child that was active most recently.',
    body: (tester) async {
      final records = [
        {'name': 'Old phone', 'pairingStatus': 'connected',
         'lastSeenAt': Timestamp.fromDate(DateTime(2026, 11, 1))},
        {'name': 'Ana', 'pairingStatus': 'connected',
         'lastSeenAt': Timestamp.fromDate(DateTime(2026, 11, 22, 8))},
      ];
      final index = pickPrimaryChildIndex(records, childLooksConnected);
      expect(index, 1);
      return 'Of "Old phone" (last seen Nov 1) and "Ana" (seen today), the '
          'dashboard opens ${records[index]['name']}';
    },
  );
}
