import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/admin_settings_api_service.dart';

/// Covers AdminSettingsApiService - previously untestable because it
/// constructed a real Dio() and called the real FirebaseAuth.instance
/// directly, with no injection seam at all. Fixed by making both
/// injectable (optional constructor params defaulting to the real
/// behavior, so the app's one real call site in admin_settings_screen.dart
/// needed no change).
///
/// No real network call is made here: each test wires the injected Dio
/// with an `InterceptorsWrapper` that intercepts onRequest and resolves
/// (or rejects) immediately with a canned response, inspecting the real
/// request Dio built (path, method, headers, body) before doing so. This
/// is a standard Dio testing technique (short-circuiting at the
/// interceptor stage, before Dio ever reaches its transport/adapter
/// layer) - deliberately chosen over faking Dio's lower-level
/// HttpClientAdapter, since this dev environment has no network access to
/// pub.dev to double-check that lower-level interface's exact shape
/// against the pinned dio version, and getting that detail wrong would
/// produce a test that fails for the wrong reason.
void main() {
  Dio dioWithInterceptor(
    void Function(RequestOptions options, RequestInterceptorHandler handler)
    onRequest,
  ) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
    return dio;
  }

  group('AdminSettingsApiService token handling', () {
    test(
      'getSettings propagates an error from the token provider without '
      'ever making a request',
      () async {
        var requestWasMade = false;
        final dio = dioWithInterceptor((options, handler) {
          requestWasMade = true;
          handler.next(options);
        });

        final service = AdminSettingsApiService(
          dio: dio,
          getAdminToken: () async => throw Exception('No authenticated user.'),
        );

        await expectLater(
          service.getSettings(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No authenticated user.'),
            ),
          ),
        );
        expect(requestWasMade, isFalse);
      },
    );

    test(
      'getSettings sends the token from the provider as a Bearer header',
      () async {
        String? capturedAuthHeader;

        final dio = dioWithInterceptor((options, handler) {
          capturedAuthHeader = options.headers['Authorization'] as String?;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'default_daily_limit_minutes': 120},
            ),
          );
        });

        final service = AdminSettingsApiService(
          dio: dio,
          getAdminToken: () async => 'test-token-123',
        );

        final result = await service.getSettings();

        expect(capturedAuthHeader, 'Bearer test-token-123');
        expect(result['default_daily_limit_minutes'], 120);
      },
    );

    test('getSettings requests GET /admin/settings/', () async {
      String? capturedPath;
      String? capturedMethod;

      final dio = dioWithInterceptor((options, handler) {
        capturedPath = options.path;
        capturedMethod = options.method;
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: {}),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      await service.getSettings();

      expect(capturedPath, '/admin/settings/');
      expect(capturedMethod, 'GET');
    });
  });

  group('AdminSettingsApiService.getOverview', () {
    test('GETs /admin/overview/ with the day range and parses the counts',
        () async {
      String? capturedPath;
      Map<String, dynamic>? capturedQuery;

      final dio = dioWithInterceptor((options, handler) {
        capturedPath = options.path;
        capturedQuery = options.queryParameters;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'daily': [
                {
                  'date': '2026-11-20',
                  'activeGuardians': 0,
                  'activeChildren': 0,
                  'recorded': false,
                },
                {
                  'date': '2026-11-21',
                  'activeGuardians': 2,
                  'activeChildren': 3,
                  'recorded': true,
                },
              ],
              'jobs': {
                'monitoring': {
                  'ok': true,
                  'lastRunAt': '2026-11-21T02:00:00+00:00',
                  'summary': {'scanned': 4},
                },
                'data_cleanup': null,
              },
              'server': {
                'version': 'abc1234',
                'running_since': '2026-11-21T01:00:00+00:00',
              },
            },
          ),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      final overview = await service.getOverview(days: 30);

      expect(capturedPath, '/admin/overview/');
      expect(capturedQuery, {'days': 30});
      expect(overview.daily, hasLength(2));
      expect(overview.daily.first.recorded, isFalse);
      expect(overview.daily.last.total, 5);
      expect(overview.daily.last.activeGuardians, 2);
      expect(overview.jobs['monitoring']!.ok, isTrue);
      expect(overview.jobs['monitoring']!.lastRunAt, isNotNull);
      expect(overview.jobs.containsKey('data_cleanup'), isTrue);
      expect(overview.jobs['data_cleanup'], isNull);
      expect(overview.serverVersion, 'abc1234');
    });

    test('tolerates missing or malformed fields', () {
      final overview = AdminOverview.fromJson({
        'daily': [
          {'date': 'not a date'},
          'junk',
        ],
        'jobs': 'junk',
      });
      expect(overview.daily, isEmpty);
      expect(overview.jobs, isEmpty);
      expect(overview.serverVersion, '-');
      expect(overview.runningSince, isNull);
    });
  });
}
