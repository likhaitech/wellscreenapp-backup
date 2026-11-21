// CASE-082 - Rule Management and Restriction
// Run: flutter test test/cases/set_app_time_limit_dialog_case_082_test.dart -r expanded

import 'package:app/screens/set_app_time_limit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-082',
    file: 'test/cases/set_app_time_limit_dialog_case_082_test.dart',
    codeTested: 'lib/screens/set_app_time_limit_dialog.dart',
    description: 'Guardian enters an invalid app time limit.',
    expected: 'Limit is not saved; “Enter a limit between 1 minute and 24 hours (0–59 minutes per hour).” is displayed.',
    body: (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1080 / 411;
      addTearDown(tester.view.reset);
      int? saved = -1;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => saved = await showSetAppTimeLimitDialog(
                  context: context,
                  appName: 'YouTube',
                  usageTodayMs: 0,
                ),
                child: const Text('Set limit'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Set limit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 25 hours 0 minutes: more than 24 hours.
      await tester.enterText(find.byType(TextField).at(0), '25');
      await tester.enterText(find.byType(TextField).at(1), '0');
      await tester.tap(find.text('Save limit'));
      await tester.pump();
      const error =
          'Enter a limit between 1 minute and 24 hours (0–59 minutes per hour).';
      expect(find.text(error), findsOneWidget);
      expect(find.text('Save limit'), findsOneWidget); // sheet still open
      expect(saved, -1); // nothing returned, nothing saved
      return 'Entered 25 h 0 m and tapped Save limit: the sheet stayed open, '
          'no limit was returned, and "$error" was shown';
    },
  );
}
