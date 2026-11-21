// CASE-133 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/sms_alert_label_case_133_test.dart -r expanded

import 'package:app/services/sms_alert_label.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-133',
    file: 'test/cases/sms_alert_label_case_133_test.dart',
    codeTested: 'lib/services/sms_alert_label.dart',
    description: 'Guardian opens SMS Backup Alerts in Reports.',
    expected: 'Each SMS backup attempt is listed with its sent or delivered status.',
    body: (tester) async {
      final shown = [for (final o in ['sent', 'delivered', 'undelivered']) smsAlertOutcomeLabel(o)];
      expect(shown, ['Sent', 'Delivered',
          'Not delivered - your phone may be off or out of signal']);
      return 'SMS attempts are listed as: ${shown.join(' / ')}';
    },
  );
}
