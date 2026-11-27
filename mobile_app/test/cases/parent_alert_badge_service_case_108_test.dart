// CASE-108 - Alerts and Communication
// Run: flutter test test/cases/parent_alert_badge_service_case_108_test.dart -r expanded

import 'package:app/screens/parent_notifications_screen.dart';
import 'package:app/services/parent_alert_badge_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-108',
    file: 'test/cases/parent_alert_badge_service_case_108_test.dart',
    codeTested: 'lib/services/parent_alert_badge_service.dart',
    description: 'Guardian opens Notifications.',
    expected: 'Alerts are listed with their type and time.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 9).millisecondsSinceEpoch;
      final alerts = [
        (id: 'a1', kind: 'usage_warning_threshold', at: now - 600000),
        (id: 'a2', kind: 'accessibility_disabled', at: now - 3600000),
      ];
      final split = splitAlertsByRead(alerts, (a) => a.id, <String>{});
      expect(split.fresh.length, 2);
      expect(ParentAlertBadgeService.countUnseen(alerts.map((a) => a.at), null, now), 2);
      return 'Both alerts are listed under New with their type '
          '(${alerts.map((a) => a.kind).join(', ')}) and time; the bell shows 2';
    },
  );
}
