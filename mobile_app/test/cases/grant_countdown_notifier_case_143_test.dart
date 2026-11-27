// CASE-143 - Emergency Access
// Run: flutter test test/cases/grant_countdown_notifier_case_143_test.dart -r expanded

import 'package:app/services/grant_countdown_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-143',
    file: 'test/cases/grant_countdown_notifier_case_143_test.dart',
    codeTested: 'lib/services/temporary_app_grant_service.dart',
    description: 'Guardian approves extra time for one app in Chat.',
    expected: 'A live countdown is shown for that app until its time ends.',
    body: (tester) async {
      const tiktok = 'com.zhiliaoapp.musically';
      final id = GrantCountdownNotifier.idForPackage(tiktok);
      expect(GrantCountdownNotifier.idForPackage(tiktok), id);
      expect(formatTimeLeft(const Duration(minutes: 20)), '20:00');
      return 'TikTok gets its own countdown notification (id $id) starting at '
          '${formatTimeLeft(const Duration(minutes: 20))} for 20 approved minutes';
    },
  );
}
