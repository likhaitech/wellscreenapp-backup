// CASE-107 - Rule Management and Restriction
// Run: flutter test test/cases/app_rules_service_case_107_test.dart -r expanded

import 'package:app/models/app_rule.dart';
import 'package:app/services/app_rules_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-107',
    file: 'test/cases/app_rules_service_case_107_test.dart',
    codeTested: 'lib/services/app_rules_service.dart',
    description: 'Child restarts the phone and opens a blocked app.',
    expected: 'The app is still blocked after the restart.',
    body: (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppRulesService().saveRulesLocally([
        AppRule(appName: 'TikTok', packageName: 'com.zhiliaoapp.musically',
            monitorEnabled: true, restrictEnabled: true),
      ]);
      // "Restart": copy what is on disk into a fresh store and a new service.
      final stored = (await SharedPreferences.getInstance()).getString(
          'restricted_packages_json');
      final rulesJson =
          (await SharedPreferences.getInstance()).getString('app_rules_json');
      SharedPreferences.setMockInitialValues({
        'restricted_packages_json': stored!,
        'app_rules_json': rulesJson!,
      });
      final after = await AppRulesService().getRules();
      expect(after.single.packageName, 'com.zhiliaoapp.musically');
      expect(after.single.restrictEnabled, isTrue);
      return 'After a restart the stored rules still block TikTok '
          '(restricted_packages_json = $stored)';
    },
  );
}
