// CASE-132 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/site_category_service_case_132_test.dart -r expanded

import 'package:app/services/site_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-132',
    file: 'test/cases/site_category_service_case_132_test.dart',
    codeTested: 'lib/services/site_category_service.dart',
    description: 'Guardian taps ⋮ > Block this site, then Remove my rule.',
    expected: 'The child is blocked from the site; after Remove my rule, the site returns to normal.',
    body: (tester) async {
      final blocked = const WebsiteRules().withRule('example.com', WebsiteRuleAction.block);
      expect(blocked.ruleFor('example.com'), WebsiteRuleAction.block);
      final removed = blocked.withRule('example.com', null);
      expect(removed.ruleFor('example.com'), isNull);
      expect(removed.blockedDomains, isEmpty);
      return 'Block this site saved example.com as blocked; Remove my rule '
          'cleared it, so the site is back to the normal checks';
    },
  );
}
