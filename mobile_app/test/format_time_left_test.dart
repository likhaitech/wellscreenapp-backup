import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/grant_countdown_notifier.dart';

void main() {
  test('minutes and seconds', () {
    expect(formatTimeLeft(const Duration(minutes: 14, seconds: 5)), '14:05');
    expect(formatTimeLeft(const Duration(seconds: 9)), '0:09');
  });

  test('hours', () {
    expect(
      formatTimeLeft(const Duration(hours: 1, minutes: 2, seconds: 30)),
      '1:02:30',
    );
  });

  test('past end shows zero', () {
    expect(formatTimeLeft(const Duration(seconds: -3)), '0:00');
  });
}
