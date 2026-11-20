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

  group('AdminSettingsApiService.applyPatch', () {
    test('POSTs the patch to /admin/settings/patch with validate_only', () async {
      Map<String, dynamic>? capturedBody;
      String? capturedPath;

      final dio = dioWithInterceptor((options, handler) {
        capturedPath = options.path;
        capturedBody = Map<String, dynamic>.from(options.data as Map);
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'valid': true, 'applied': false, 'changes': {'minimum_app_version': '1.4.0'}},
          ),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      final result = await service.applyPatch(
        {'settings': {'minimum_app_version': '1.4.0'}},
        validateOnly: true,
      );

      expect(capturedPath, '/admin/settings/patch');
      expect(capturedBody, {
        'settings': {'minimum_app_version': '1.4.0'},
        'validate_only': true,
      });
      expect(result['applied'], false);
    });

    test('a 422 from the server becomes SystemPatchRejected', () async {
      final dio = dioWithInterceptor((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 422,
              data: {
                'detail': {
                  'message': 'Patch rejected',
                  'errors': ['settings.minimum_app_version: String should match pattern'],
                },
              },
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      await expectLater(
        service.applyPatch(
          {'settings': {'minimum_app_version': '1.4'}},
          validateOnly: false,
        ),
        throwsA(isA<SystemPatchRejected>()),
      );
    });
  });
}
