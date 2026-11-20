import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

class AdminSettingsApiService {
  // Both params are injectable so tests can supply a Dio wired to a fake
  // interceptor (no real network call) and a canned token function
  // (no real Firebase Auth / platform channels), without changing
  // behavior for the app's real callers, who get exactly the same Dio
  // config and the same real-FirebaseAuth token flow as before - both
  // params are optional and default to that real behavior.
  AdminSettingsApiService({Dio? dio, Future<String> Function()? getAdminToken})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // Was hardcoded to the Android-emulator-only address
              // 'http://10.0.2.2:8000' - moved to AppConfig.backendBaseUrl so
              // this and the new push-notification client (see
              // alert_notification_client.dart) share one place to update once
              // the backend is actually deployed, instead of two.
              baseUrl: AppConfig.backendBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          ),
      _getAdminTokenOverride = getAdminToken;

  final Dio _dio;
  final Future<String> Function()? _getAdminTokenOverride;

  Future<String> _getAdminToken() async {
    if (_getAdminTokenOverride != null) {
      return _getAdminTokenOverride();
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    final tokenResult = await user.getIdTokenResult(true);
    final token = tokenResult.token;

    if (token == null || token.isEmpty) {
      throw Exception('Unable to get Firebase ID token.');
    }

    return token;
  }

  Future<Map<String, dynamic>> getSettings() async {
    final token = await _getAdminToken();

    final response = await _dio.get(
      '/admin/settings/',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return Map<String, dynamic>.from(response.data);
  }

  /// Validates (and optionally applies) a system patch. Throws
  /// [SystemPatchRejected] with the server's error list when invalid.
  Future<Map<String, dynamic>> applyPatch(
    Map<String, dynamic> patch, {
    required bool validateOnly,
  }) async {
    final token = await _getAdminToken();

    try {
      final response = await _dio.post(
        '/admin/settings/patch',
        data: {...patch, 'validate_only': validateOnly},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      final data = e.response?.data;

      if (e.response?.statusCode == 422 && data is Map) {
        final detail = data['detail'];

        if (detail is Map && detail['errors'] is List) {
          throw SystemPatchRejected(
            (detail['errors'] as List).map((x) => x.toString()).toList(),
          );
        }

        if (detail is List) {
          throw SystemPatchRejected(
            detail.map((x) => (x is Map ? x['msg'] : x).toString()).toList(),
          );
        }
      }

      rethrow;
    }
  }
}

class SystemPatchRejected implements Exception {
  SystemPatchRejected(this.errors);

  final List<String> errors;
}
