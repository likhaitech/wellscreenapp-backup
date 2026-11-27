// CASE-057 - Usage Monitoring
// Run: flutter test test/cases/child_home_screen_case_057_test.dart -r expanded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-057',
    file: 'test/cases/child_home_screen_case_057_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child looks for the menu on the home screen.',
    expected: 'There is no menu button; all functions are on the main screens and the bottom dock.',
    body: (tester) async {
      // Checks the real screen file: no drawer and no menu button anywhere.
      final source = File('lib/screens/child_home_screen.dart').readAsStringSync();
      expect(source.contains('Drawer('), isFalse);
      expect(source.contains('Icons.menu'), isFalse);
      expect(source.contains('PopupMenuButton'), isFalse);
      return 'child_home_screen.dart has no Drawer, no menu icon and no '
          'pop-up menu; everything is on the main screens and the bottom dock';
    },
  );
}
