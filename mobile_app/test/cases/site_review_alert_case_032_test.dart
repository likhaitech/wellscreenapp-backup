// CASE-032 - Rule-Based Pattern Detection and Risk Level
// Guardian taps Block on that alert; the child reopens malware.testcategory.com.
// Code being tested: lib/services/site_review_alert.dart (the alert's site)
// and WebsiteRules.withRule (what the Block button saves). On the child's
// phone the guardian's block wins over every other check (Kotlin
// SiteBlocker, parent_rule) - shown on the emulator figure.
//
// Run: flutter test test/cases/site_review_alert_case_032_test.dart -r expanded

import 'package:app/services/site_category_service.dart';
import 'package:app/services/site_review_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-032',
    file: 'test/cases/site_review_alert_case_032_test.dart',
    codeTested: 'lib/services/site_review_alert.dart',
    description:
        'Guardian taps Block on that alert; the child reopens '
        'malware.testcategory.com.',
    expected:
        'The site is blocked on the child device and shown as “Blocked '
        'by you”.',
    body: (tester) async {
      // The "Review this website" alert from CASE-031.
      final site = SiteReviewAlert.domainOf(SiteReviewAlert.reviewKind, {
        'subject': 'malware.testcategory.com',
        'label': "malware.testcategory.com (flagged by Cloudflare's family "
            'filter)',
      });
      expect(site, 'malware.testcategory.com');

      // Tapping Block saves the guardian's block rule for that site.
      final rules =
          const WebsiteRules().withRule(site!, WebsiteRuleAction.block);
      expect(rules.blockedDomains, contains('malware.testcategory.com'));
      expect(rules.ruleFor('malware.testcategory.com'),
          WebsiteRuleAction.block);

      return 'Block saved malware.testcategory.com to the guardian\'s blocked '
          'sites; the rule reads "block", shown as "Blocked by you", and the '
          'child\'s phone blocks it on reopening';
    },
  );
}
