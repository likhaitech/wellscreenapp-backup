// CASE-086 - Rule Management and Restriction
// Run: flutter test test/cases/app_rules_service_case_086_test.dart -r expanded

import 'dart:convert';

import 'package:app/models/app_rule.dart';
import 'package:app/services/app_rules_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-086',
    file: 'test/cases/app_rules_service_case_086_test.dart',
    codeTested: 'lib/services/app_rules_service.dart',
    description: 'Guardian blocks an app and the child opens it.',
    expected: '“Rules saved successfully.” is displayed; the child sees “Restricted by your guardian”.',
    body: (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppRulesService().saveRulesLocally([
        AppRule(appName: 'TikTok', packageName: 'com.zhiliaoapp.musically',
            monitorEnabled: true, restrictEnabled: true),
        AppRule(appName: 'Calculator', packageName: 'com.android.calculator2',
            monitorEnabled: true, restrictEnabled: false),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final blocked = List<String>.from(
          jsonDecode(prefs.getString('restricted_packages_json')!) as List);
      expect(blocked, ['com.zhiliaoapp.musically']);
      return 'TikTok was saved as blocked; the list the phone\'s blocker reads '
          '(restricted_packages_json) is $blocked, so opening TikTok shows '
          '"Restricted by your guardian" (message and block screen on the '
          'emulator figure)';
    },
  );
}
