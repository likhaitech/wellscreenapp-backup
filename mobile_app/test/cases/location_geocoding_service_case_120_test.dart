// CASE-120 - Location Tracking
// Run: flutter test test/cases/location_geocoding_service_case_120_test.dart -r expanded

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/location_geocoding_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

/// Answers like OpenStreetMap's address lookup, without the internet.
class _MapServer implements HttpClientAdapter {
  RequestOptions? asked;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked = options;
    return ResponseBody.fromString(
      jsonEncode({
        'display_name': 'Gorordo Avenue, Lahug, Cebu City, Cebu, 6000, Philippines',
        'address': {
          'road': 'Gorordo Avenue',
          'suburb': 'Lahug',
          'city': 'Cebu City',
          'state': 'Cebu',
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testCase(
    'CASE-120',
    file: 'test/cases/location_geocoding_service_case_120_test.dart',
    codeTested: 'lib/services/location_geocoding_service.dart',
    description: 'Guardian opens Live Location.',
    expected: 'The child’s location is shown on the map with its address.',
    body: (tester) async {
      final server = _MapServer();
      final dio = Dio()..httpClientAdapter = server;
      final address = await tester.runAsync(
        () => LocationGeocodingService(dio: dio)
            .reverseGeocode(latitude: 10.3297, longitude: 123.9018),
      );
      expect(address, 'Gorordo Avenue, Lahug, Cebu City');
      expect(server.asked!.queryParameters['lat'], 10.3297);
      return 'Location 10.3297, 123.9018 is shown with the address "$address"';
    },
  );
}
