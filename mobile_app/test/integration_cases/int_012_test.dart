// INT-012 - Location Tracking Module -> Dashboard, Reports, and Recommendations Module
// Send the child device location update.
// Code being tested: lib/services/child_location_text.dart, lib/utils/location_age.dart
//
// Run: flutter test test/integration_cases/int_012_test.dart -r expanded

import 'package:app/services/child_location_text.dart';
import 'package:app/utils/location_age.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cases/case_report.dart';

void main() {
  testCase(
    'INT-012',
    file: 'test/integration_cases/int_012_test.dart',
    codeTested:
        'lib/services/child_location_text.dart + lib/utils/location_age.dart',
    description: 'Send the child device location update '
        '(Location Tracking -> Dashboard, Reports, and Recommendations).',
    expected: 'The current or last known location of the child device is '
        'shown to the guardian.',
    body: (tester) async {

      final sharedAt = DateTime(2026, 11, 22, 16, 40);
      final profile = <String, dynamic>{
        'latestLocation': {
          'label': 'Lahug, Cebu City',
          'latitude': 10.33,
          'longitude': 123.9,
        },
        'locationUpdatedAt': Timestamp.fromDate(sharedAt),
      };


      expect(locationTextOf(profile), 'Lahug, Cebu City');
      final updated = locationUpdatedTextOf(profile);
      expect(updated, '11/22/2026 16:40');
      expect(
        locationAgeWarning(
            hasLocation: true,
            updatedAt: updated,
            now: sharedAt.add(const Duration(minutes: 20))),
        isNull,
      );
      final stale = locationAgeWarning(
          hasLocation: true,
          updatedAt: updated,
          now: sharedAt.add(const Duration(hours: 2)));
      expect(stale,
          "Location is 2 hours old - the child's app may be closed or location is off.");
      return 'The shared location "Lahug, Cebu City" ($updated) is shown to '
          'the guardian; two hours later it is shown as the last known '
          'location with "$stale"';
    },
  );
}
