// CASE-159 - System Administration
// Run: flutter test test/cases/admin_activity_widgets_case_159_test.dart -r expanded

import 'dart:io';

import 'package:app/services/admin_overview_api_service.dart';
import 'package:app/widgets/admin_activity_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-159',
    file: 'test/cases/admin_activity_widgets_case_159_test.dart',
    codeTested: 'lib/widgets/admin_activity_widgets.dart',
    description: 'Administrator opens the Active users graph on the admin home.',
    expected: 'Guardians and child devices active per day are shown; the graph refreshes every 60 seconds.',
    body: (tester) async {
      AdminDailyActive day(int d, int g, int c) => AdminDailyActive(
            date: DateTime(2026, 11, d),
            activeGuardians: g,
            activeChildren: c,
            recorded: true,
          );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminActiveUsersChart(
              days: [day(20, 1, 1), day(21, 2, 3)],
              range: 7,
              onRangeChanged: (_) {},
            ),
          ),
        ),
      ));
      expect(find.text('Guardians'), findsOneWidget);
      expect(find.text('Child devices'), findsOneWidget);
      final selected = find.byKey(const Key('adminChartSelected'));
      expect(tester.widget<Text>(selected).textSpan!.toPlainText(), contains('5 active'));
      final home = File('lib/screens/admin_home_screen.dart').readAsStringSync();
      expect(home.contains('Duration(seconds: 60)'), isTrue);
      return 'The graph shows Guardians and Child devices per day (21 Nov: 5 '
          'active) and the admin home reloads it every 60 seconds';
    },
  );
}
