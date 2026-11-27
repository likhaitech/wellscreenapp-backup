// CASE-171 - System Administration
// Run: flutter test test/cases/admin_health_screen_case_171_test.dart -r expanded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-171',
    file: 'test/cases/admin_health_screen_case_171_test.dart',
    codeTested: 'lib/screens/admin_health_screen.dart',
    description: 'Administrator views Recent errors and Server updates, then taps View logs.',
    expected: 'Recent errors and server updates are listed (or “No errors recorded.”); View logs opens System logs.',
    body: (tester) async {
      final source = File('lib/screens/admin_health_screen.dart').readAsStringSync();
      for (final text in ['Recent errors', 'Server updates', 'No errors recorded.', 'View logs']) {
        expect(source.contains(text), isTrue, reason: text);
      }
      final home = File('lib/screens/admin_home_screen.dart').readAsStringSync();
      expect(home.contains('onViewLogs: () => _goTo(3)'), isTrue);
      expect(home.contains('AdminLogsScreen(embedded: true)'), isTrue);
      return 'System health lists Recent errors and Server updates (or "No '
          'errors recorded."), and View logs opens the System logs screen';
    },
  );
}
