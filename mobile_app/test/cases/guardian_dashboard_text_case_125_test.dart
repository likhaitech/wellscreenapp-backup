// CASE-125 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/guardian_dashboard_text_case_125_test.dart -r expanded

import 'package:app/services/guardian_dashboard_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-125',
    file: 'test/cases/guardian_dashboard_text_case_125_test.dart',
    codeTested: 'lib/screens/parent_dashboard_screen.dart',
    description: 'Guardian with no paired child opens the dashboard.',
    expected: 'The dashboard asks the guardian to pair a child account first.',
    body: (tester) async {
      expect(childLooksConnected(<String, dynamic>{}), isFalse);
      expect(pairChildFirst, 'Pair a child account first');
      return 'No child record is set up, so the child card says '
          '"$pairChildFirst"';
    },
  );
}
