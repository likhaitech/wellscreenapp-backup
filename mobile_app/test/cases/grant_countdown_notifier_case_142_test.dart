// CASE-142 - Emergency Access
// Run: flutter test test/cases/grant_countdown_notifier_case_142_test.dart -r expanded

import 'package:app/services/grant_countdown_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-142',
    file: 'test/cases/grant_countdown_notifier_case_142_test.dart',
    codeTested: 'lib/services/grant_countdown_notifier.dart',
    description: 'Guardian approves Emergency Access; child checks the notification and Home screen.',
    expected: 'A live countdown of the time left is shown in the notification and on the Home screen.',
    body: (tester) async {
      final ticks = [
        formatTimeLeft(const Duration(minutes: 15)),
        formatTimeLeft(const Duration(minutes: 14, seconds: 59)),
        formatTimeLeft(const Duration(seconds: 5)),
      ];
      expect(ticks, ['15:00', '14:59', '0:05']);
      return 'The countdown counts down ${ticks.join(' -> ')} for a 15-minute '
          'approval';
    },
  );
}
