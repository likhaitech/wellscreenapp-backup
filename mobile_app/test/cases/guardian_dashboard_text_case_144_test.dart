// CASE-144 - Emergency Access
// Run: flutter test test/cases/guardian_dashboard_text_case_144_test.dart -r expanded

import 'package:app/services/guardian_dashboard_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-144',
    file: 'test/cases/guardian_dashboard_text_case_144_test.dart',
    codeTested: 'lib/screens/parent_dashboard_screen.dart',
    description: 'Guardian opens the request and taps Approve...',
    expected: 'The guardian sees “Asked for 15 min” and can approve any time from 1 to 120 minutes.',
    body: (tester) async {
      expect(askedForLabel(15), 'Asked for 15 min');
      expect(emergencyMinuteChoices(15), contains(15));
      expect(isValidEmergencyMinutes(1), isTrue);
      expect(isValidEmergencyMinutes(120), isTrue);
      expect(isValidEmergencyMinutes(121), isFalse);
      return '"${askedForLabel(15)}" is shown; choices '
          '${emergencyMinuteChoices(15).join(', ')} min, or any typed time 1-120';
    },
  );
}
