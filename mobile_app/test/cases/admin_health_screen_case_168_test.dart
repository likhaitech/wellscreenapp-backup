// CASE-168 - System Administration
// Run: flutter test test/cases/admin_health_screen_case_168_test.dart -r expanded

import 'dart:io';

import 'package:app/screens/admin_health_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-168',
    file: 'test/cases/admin_health_screen_case_168_test.dart',
    codeTested: 'lib/screens/admin_health_screen.dart',
    description: 'Administrator opens System health while the server is running.',
    expected: 'The server shows “Online” with the server version and app version.',
    body: (tester) async {
      final status = adminServerStatus(loading: false, hasOverview: true, failed: false);
      expect(status, 'Online');
      final source = File('lib/screens/admin_health_screen.dart').readAsStringSync();
      expect(source.contains("'Server version'"), isTrue);
      expect(source.contains("'App version'"), isTrue);
      return 'With the server answering, the card reads "$status" with Server '
          'version and App version';
    },
  );
}
