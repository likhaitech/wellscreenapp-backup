import 'package:app/services/admin_settings_api_service.dart';
import 'package:app/widgets/admin_activity_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

AdminDailyActive _day(int d, int g, int c, {bool recorded = true}) =>
    AdminDailyActive(
      date: DateTime(2026, 11, d),
      activeGuardians: g,
      activeChildren: c,
      recorded: recorded,
    );

void main() {
  group('AdminActiveUsersChart', () {
    testWidgets('says so when nothing was recorded instead of drawing zeros',
        (tester) async {
      await tester.pumpWidget(_host(AdminActiveUsersChart(
        days: [_day(20, 0, 0, recorded: false), _day(21, 0, 0, recorded: false)],
        range: 7,
        onRangeChanged: (_) {},
      )));
      expect(find.textContaining('No activity recorded yet'), findsOneWidget);
    });

    testWidgets('shows the latest day, and a tapped day', (tester) async {
      await tester.pumpWidget(_host(AdminActiveUsersChart(
        days: [_day(19, 1, 1), _day(20, 0, 0, recorded: false), _day(21, 2, 3)],
        range: 7,
        onRangeChanged: (_) {},
      )));
      final selected = find.byKey(const Key('adminChartSelected'));
      expect(
        tester.widget<Text>(selected).textSpan!.toPlainText(),
        contains('5 active'),
      );
      expect(
        tester.widget<Text>(selected).textSpan!.toPlainText(),
        contains('2 guardians, 3 child devices'),
      );

      await tester.tap(find.byKey(const ValueKey('adminChartBar1')));
      await tester.pump();
      expect(
        tester.widget<Text>(selected).textSpan!.toPlainText(),
        contains('No record'),
      );
    });

    testWidgets('the range chips ask for 7 or 30 days', (tester) async {
      int? asked;
      await tester.pumpWidget(_host(AdminActiveUsersChart(
        days: [_day(21, 1, 0)],
        range: 7,
        onRangeChanged: (v) => asked = v,
      )));
      await tester.tap(find.text('30 days'));
      expect(asked, 30);
    });
  });

  group('AdminJobHealthCard', () {
    final now = DateTime(2026, 11, 21, 10, 0);

    test('status: not set up, failed, late and OK', () {
      expect(
        AdminJobHealthCard.status(null, lateAfterMinutes: 15, now: now).$1,
        'Not set up',
      );
      expect(
        AdminJobHealthCard.status(
          AdminJobStatus(ok: false, lastRunAt: now),
          lateAfterMinutes: 15,
          now: now,
        ).$1,
        'Failed',
      );
      expect(
        AdminJobHealthCard.status(
          AdminJobStatus(
            ok: true,
            lastRunAt: now.subtract(const Duration(minutes: 40)),
          ),
          lateAfterMinutes: 15,
          now: now,
        ).$1,
        'Late',
      );
      expect(
        AdminJobHealthCard.status(
          AdminJobStatus(
            ok: true,
            lastRunAt: now.subtract(const Duration(minutes: 3)),
          ),
          lateAfterMinutes: 15,
          now: now,
        ).$1,
        'OK',
      );
    });

    test('last run labels', () {
      expect(AdminJobHealthCard.lastRunLabel(null, now), 'Never ran');
      expect(
        AdminJobHealthCard.lastRunLabel(
          now.subtract(const Duration(minutes: 4)),
          now,
        ),
        'Last run 4 min ago',
      );
      expect(
        AdminJobHealthCard.lastRunLabel(
          now.subtract(const Duration(hours: 3)),
          now,
        ),
        'Last run 3 h ago',
      );
    });

    testWidgets('lists the three backend jobs', (tester) async {
      await tester.pumpWidget(_host(AdminJobHealthCard(
        jobs: {
          'monitoring': AdminJobStatus(
            ok: true,
            lastRunAt: now.subtract(const Duration(minutes: 2)),
          ),
          'chat_notifications': AdminJobStatus(ok: false, lastRunAt: now),
          'data_cleanup': null,
        },
        now: now,
      )));
      expect(find.text('Monitoring check'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Not set up'), findsOneWidget);
    });
  });
}
