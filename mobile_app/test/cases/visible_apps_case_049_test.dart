// CASE-049 - Usage Monitoring
// Run: flutter test test/cases/visible_apps_case_049_test.dart -r expanded

import 'package:app/services/usage_tracking_service.dart';
import 'package:app/services/visible_apps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-049',
    file: 'test/cases/visible_apps_case_049_test.dart',
    codeTested: 'lib/services/usage_tracking_service.dart',
    description: 'Child opens the home screen after using apps.',
    expected: 'Top Apps Today shows the three most used apps, with system apps hidden.',
    body: (tester) async {
      const min = 60000;
      final all = UsageTrackingService().summarizeAllUsage({
        'com.sec.android.app.launcher': 90 * min, // home screen
        'com.android.settings': 30 * min,
        'com.google.android.youtube': 50 * min,
        'com.zhiliaoapp.musically': 40 * min,
        'com.roblox.client': 25 * min,
        'com.android.chrome': 10 * min,
      });
      final top = visibleUserApps(all).take(3).map((a) => a.packageName).toList();
      expect(top, ['com.google.android.youtube', 'com.zhiliaoapp.musically',
          'com.roblox.client']);
      return 'Top Apps Today: YouTube, TikTok, Roblox; the launcher (90 min) '
          'and Settings were hidden';
    },
  );
}
