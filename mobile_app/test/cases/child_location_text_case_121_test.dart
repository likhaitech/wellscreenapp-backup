// CASE-121 - Location Tracking
// Run: flutter test test/cases/child_location_text_case_121_test.dart -r expanded

import 'package:app/services/child_location_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-121',
    file: 'test/cases/child_location_text_case_121_test.dart',
    codeTested: 'lib/screens/gps_map_screen.dart',
    description: 'Child device goes offline; guardian opens the location.',
    expected: 'The last known location and its time are shown.',
    body: (tester) async {
      final profile = <String, dynamic>{
        'latestLocation': {'label': 'Lahug, Cebu City', 'latitude': 10.33, 'longitude': 123.9},
        'locationUpdatedAt': Timestamp.fromDate(DateTime(2026, 11, 22, 7, 45)),
      };
      expect(locationTextOf(profile), 'Lahug, Cebu City');
      expect(locationUpdatedTextOf(profile), '11/22/2026 07:45');
      return 'With the child offline the map shows the last known place '
          '"${locationTextOf(profile)}", updated ${locationUpdatedTextOf(profile)}';
    },
  );
}
