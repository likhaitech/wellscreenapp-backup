// CASE-113 - Alerts and Communication
// Run: flutter test test/cases/parent_alert_badge_service_case_113_test.dart -r expanded

import 'package:app/screens/parent_notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-113',
    file: 'test/cases/parent_alert_badge_service_case_113_test.dart',
    codeTested: 'lib/services/parent_alert_badge_service.dart',
    description: 'Guardian opens Notifications after reading earlier alerts.',
    expected: 'Earlier alerts are listed under “Previously viewed”.',
    body: (tester) async {
      final split = splitAlertsByRead(
        ['p1:old-1', 'p1:old-2', 'p1:new-1'],
        (key) => key,
        {'p1:old-1', 'p1:old-2'},
      );
      expect(split.viewed, ['p1:old-1', 'p1:old-2']);
      expect(split.fresh, ['p1:new-1']);
      return 'The two alerts already read are under "Previously viewed"; '
          'the new one stays under New';
    },
  );
}
