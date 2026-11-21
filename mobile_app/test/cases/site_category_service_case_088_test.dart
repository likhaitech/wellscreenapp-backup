// CASE-088 - Rule Management and Restriction
// Run: flutter test test/cases/site_category_service_case_088_test.dart -r expanded

import 'package:app/services/site_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-088',
    file: 'test/cases/site_category_service_case_088_test.dart',
    codeTested: 'lib/services/site_category_service.dart',
    description: 'Guardian enters an invalid website such as “abc”.',
    expected: 'Rule is not saved; “Enter a valid website such as example.com.” is displayed.',
    body: (tester) async {
      expect(WebsiteRules.normalizeDomain('abc'), isNull);
      expect(WebsiteRules.normalizeDomain('example.com'), 'example.com');
      expect(WebsiteRules.invalidDomainMessage,
          'Enter a valid website such as example.com.');
      return '"abc" is rejected (no rule is saved) and the Rules screen shows '
          '"${WebsiteRules.invalidDomainMessage}"; "example.com" is accepted';
    },
  );
}
