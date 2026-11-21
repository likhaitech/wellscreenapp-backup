// CASE-057 - Rule Management and Restriction
// Run: flutter test test/cases/site_review_alert_case_057_test.dart -r expanded

import 'package:app/services/site_category_service.dart';
import 'package:app/services/site_review_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-057',
    file: 'test/cases/site_review_alert_case_057_test.dart',
    codeTested: 'lib/services/site_review_alert.dart',
    description: 'Guardian taps Allow on a “Review this website” or ask-to-allow alert.',
    expected: 'A website rule is saved and the site opens on the child device.',
    body: (tester) async {
      final site = SiteReviewAlert.domainOf(SiteReviewAlert.reviewKind, {
        'subject': 'malware.testcategory.com',
      })!;
      final saved =
          const WebsiteRules().withRule(site, WebsiteRuleAction.allow);
      expect(saved.allowedDomains, [site]);
      expect(saved.ruleFor(site), WebsiteRuleAction.allow);
      expect(saved.isAllowed(site), isTrue);
      return 'Allow saved $site to Allowed websites; the guardian\'s Allow '
          'comes first on the child phone, so the site opens (CASE-052)';
    },
  );
}
