// CASE-031 - Profile Management
// Run: flutter test test/cases/privacy_text_case_031_test.dart -r expanded

import 'package:app/services/privacy_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-031',
    file: 'test/cases/privacy_text_case_031_test.dart',
    codeTested: 'lib/services/privacy_text.dart',
    description: 'Guardian opens Privacy Boundary.',
    expected: 'The notice lists what is collected and states that page text is checked on the phone and never saved or sent.',
    body: (tester) async {
      const body = PrivacyText.guardianWebsiteBody;
      expect(PrivacyText.guardianWebsiteTitle, 'Website names only');
      expect(body, contains('checked on the child\'s phone'));
      expect(body, contains('never saved or sent'));
      expect(body, contains('Never the full address'));
      return 'Privacy Boundary says: website names only, never the full '
          'address; page words are checked on the child\'s phone and never '
          'saved or sent';
    },
  );
}
