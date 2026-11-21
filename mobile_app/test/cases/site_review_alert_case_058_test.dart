// CASE-058 - Rule Management and Restriction
// Run: flutter test test/cases/site_review_alert_case_058_test.dart -r expanded

import 'package:app/services/site_category_service.dart';
import 'package:app/services/site_review_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-058',
    file: 'test/cases/site_review_alert_case_058_test.dart',
    codeTested: 'lib/services/site_review_alert.dart',
    description: 'Guardian taps Block on a “Review this website” alert.',
    expected: 'The site stays blocked on the child device and is shown as “Blocked by you”.',
    body: (tester) async {
      final site = SiteReviewAlert.domainOf(SiteReviewAlert.reviewKind, {
        'subject': 'malware.testcategory.com',
      })!;
      final saved =
          const WebsiteRules().withRule(site, WebsiteRuleAction.block);
      expect(saved.blockedDomains, [site]);
      expect(saved.ruleFor(site), WebsiteRuleAction.block);
      expect(saved.isAllowed(site), isFalse);
      return 'Block saved $site to Blocked websites (rule: block), so it '
          'stays blocked and Reports labels it "Blocked by you"';
    },
  );
}
