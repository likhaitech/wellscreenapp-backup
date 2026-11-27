// CASE-128 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/guardian_dashboard_text_case_128_test.dart -r expanded

import 'package:app/services/guardian_dashboard_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-128',
    file: 'test/cases/guardian_dashboard_text_case_128_test.dart',
    codeTested: 'lib/screens/parent_dashboard_screen.dart',
    description: 'Child turns off Usage Access.',
    expected: 'The dashboard shows “Usage Access off” in the protection status.',
    body: (tester) async {
      final labels = protectionStatusLabels({
        'accessibilityEnabled': true,
        'usageAccessEnabled': false,
      });
      expect(labels, contains('Usage Access off'));
      return 'Protection status shows: ${labels.join(', ')}';
    },
  );
}
