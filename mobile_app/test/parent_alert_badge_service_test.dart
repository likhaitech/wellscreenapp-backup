import 'package:app/services/parent_alert_badge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const now = 1000000000000;
  const hour = 3600000;

  test('counts alerts created after the guardian last opened Notifications', () {
    expect(
      ParentAlertBadgeService.countUnseen(
        [now - 3 * hour, now - hour, now - 60000],
        now - 2 * hour,
        now,
      ),
      2,
    );
    expect(
      ParentAlertBadgeService.countUnseen([now - hour], now, now),
      0,
    );
  });

  test('never opened: only the last 24 hours count', () {
    expect(
      ParentAlertBadgeService.countUnseen(
        [now - 30 * hour, now - 5 * hour],
        null,
        now,
      ),
      1,
    );
  });
}
