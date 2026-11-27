// CASE-091 - Rule Management and Restriction
// Run: flutter test test/cases/quick_block_sites_case_091_test.dart -r expanded

import 'package:app/services/quick_block_sites.dart';
import 'package:app/services/site_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-091',
    file: 'test/cases/quick_block_sites_case_091_test.dart',
    codeTested: 'lib/services/quick_block_sites.dart',
    description: 'Guardian taps Quick block for TikTok.',
    expected: 'All TikTok websites are blocked on the child device.',
    body: (tester) async {
      final tiktok = quickBlockSites.firstWhere((s) => s.name == 'TikTok');
      var rules = const WebsiteRules();
      expect(tiktok.isBlockedIn(rules.blockedDomains), isFalse);
      for (final domain in tiktok.domains) {
        rules = rules.withRule(domain, WebsiteRuleAction.block);
      }
      expect(tiktok.isBlockedIn(rules.blockedDomains), isTrue);
      expect(rules.ruleFor('www.tiktok.com'), WebsiteRuleAction.block);
      return 'Quick block TikTok saved ${tiktok.domains} to Blocked websites; '
          'TikTok now shows as blocked (subdomains are covered by the child '
          'phone\'s blocker, CASE-089)';
    },
  );
}
