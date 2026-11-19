import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/location_age.dart';

void main() {
  final now = DateTime(2026, 11, 19, 15, 0);

  String? warning(String timestamp, {bool hasLocation = true}) {
    return locationAgeWarning(
      hasLocation: hasLocation,
      updatedAt: timestamp,
      now: now,
    );
  }

  test('recent location does not show a warning', () {
    expect(warning('11/19/2026 14:50'), isNull);
  });

  test('exactly one hour old does not show a warning', () {
    expect(warning('11/19/2026 14:00'), isNull);
  });

  test('location older than one hour shows a warning', () {
    expect(warning('11/19/2026 13:59'), contains('1 hour old'));
  });

  test('two-hour-old location shows a warning', () {
    expect(warning('11/19/2026 13:00'), contains('2 hours old'));
  });

  test('three-hour-old location shows a warning', () {
    expect(warning('11/19/2026 12:00'), contains('3 hours old'));
  });

  test('missing location displays empty state', () {
    expect(
      warning('', hasLocation: false),
      'No location shared yet.',
    );
  });

  test('missing timestamp is handled safely', () {
    expect(
      warning('Waiting for update'),
      'Location update time unavailable.',
    );
  });

  test('invalid calendar date is rejected', () {
    expect(parseLocationUpdatedAt('02/30/2026 12:00'), isNull);
  });

  test('future timestamp is handled safely', () {
    expect(
      warning('11/19/2026 16:00'),
      'Location update time unavailable.',
    );
  });
}