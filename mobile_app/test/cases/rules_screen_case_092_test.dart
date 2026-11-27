// CASE-092 - Rule Management and Restriction
// Run: flutter test test/cases/rules_screen_case_092_test.dart -r expanded

import 'package:app/screens/rules/rules_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-092',
    file: 'test/cases/rules_screen_case_092_test.dart',
    codeTested: 'lib/screens/rules/rules_screen.dart',
    description: 'Guardian opens the website rules.',
    expected: '“Harmful sites are blocked automatically” is shown with no switch to turn it off.',
    body: (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HarmfulSitesNotice()),
      ));
      expect(find.text('Harmful sites are blocked automatically'),
          findsOneWidget);
      expect(find.text('Always on'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      return 'The website rules show "Harmful sites are blocked '
          'automatically" with an "Always on" badge; no switch or checkbox '
          'is present';
    },
  );
}
