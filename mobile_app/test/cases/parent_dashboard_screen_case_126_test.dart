// CASE-126 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/parent_dashboard_screen_case_126_test.dart -r expanded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-126',
    file: 'test/cases/parent_dashboard_screen_case_126_test.dart',
    codeTested: 'lib/screens/parent_dashboard_screen.dart',
    description: 'Guardian looks for the menu on the dashboard.',
    expected: 'There is no menu button; Home, Chat, Devices, Reports, and Settings are on the bottom dock.',
    body: (tester) async {
      final source = File('lib/screens/parent_dashboard_screen.dart').readAsStringSync();
      expect(source.contains('Drawer('), isFalse);
      expect(source.contains('Icons.menu'), isFalse);
      for (final tab in ['Home', 'Chat', 'Devices', 'Reports', 'Settings']) {
        expect(source.contains("'$tab'"), isTrue, reason: tab);
      }
      return 'parent_dashboard_screen.dart has no drawer and no menu icon; the '
          'dock lists Home, Chat, Devices, Reports and Settings';
    },
  );
}
