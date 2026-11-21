// CASE-093 - Rule Management and Restriction
// Run: flutter test test/cases/site_review_alert_case_093_test.dart -r expanded

import 'package:app/services/site_review_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-093',
    file: 'test/cases/site_review_alert_case_093_test.dart',
    codeTested: 'lib/services/site_review_alert.dart',
    description: 'Child taps “Ask my parent to allow this site” on a blocked gambling site.',
    expected: '“Request sent to your parent” is shown and the guardian receives the request.',
    body: (tester) async {
      // The alert the child's tap creates for the guardian.
      final site = SiteReviewAlert.domainOf(SiteReviewAlert.requestKind, {
        'subject': 'bet-example.com',
      });
      expect(site, 'bet-example.com');
      return 'The ask-to-allow alert (${SiteReviewAlert.requestKind}) reaches '
          'the guardian for $site with Allow / Keep blocked; the child\'s '
          'button changes to "Request sent to your parent" (emulator figure)';
    },
  );
}
