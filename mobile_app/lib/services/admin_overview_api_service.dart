import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

/// The admin dashboard and System health data (GET /admin/overview).
/// Read only: the admin app cannot change the system.
class AdminOverviewApiService {
  // Both params are injectable so tests can supply a Dio wired to a fake
  // interceptor (no real network call) and a canned token function
  // (no real Firebase Auth / platform channels), without changing
  // behavior for the app's real callers, who get exactly the same Dio
  // config and the same real-FirebaseAuth token flow as before - both
  // params are optional and default to that real behavior.
  AdminOverviewApiService({Dio? dio, Future<String> Function()? getAdminToken})
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

  /// Dashboard data: daily active totals for the last [days] days (7 or
  /// 30) and the last run of each background job. Counts only.
  Future<AdminOverview> getOverview({int days = 7}) async {
    final token = await _getAdminToken();

    final response = await _dio.get(
      '/admin/overview/',
      queryParameters: {'days': days},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return AdminOverview.fromJson(Map<String, dynamic>.from(response.data));
  }
}

/// One day of the active-users graph. [recorded] is false when the
/// monitoring check did not run that day (shown as "no record", not 0).
class AdminDailyActive {
  const AdminDailyActive({
    required this.date,
    required this.activeGuardians,
    required this.activeChildren,
    required this.recorded,
  });

  final DateTime date;
  final int activeGuardians;
  final int activeChildren;
  final bool recorded;

  int get total => activeGuardians + activeChildren;
}

/// Last run of a background job (monitoring check, chat notifications,
/// data cleanup).
class AdminJobStatus {
  const AdminJobStatus({required this.ok, required this.lastRunAt});

  final bool ok;
  final DateTime? lastRunAt;
}

class AdminOverview {
  const AdminOverview({
    required this.daily,
    required this.jobs,
    required this.serverVersion,
    required this.runningSince,
  });

  /// Oldest day first.
  final List<AdminDailyActive> daily;

  /// Job name -> status, or null when the job has never run (not set up).
  final Map<String, AdminJobStatus?> jobs;
  final String serverVersion;
  final DateTime? runningSince;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final daily = <AdminDailyActive>[];
    final rawDaily = json['daily'];
    if (rawDaily is List) {
      for (final item in rawDaily) {
        if (item is! Map) continue;
        final date = DateTime.tryParse((item['date'] ?? '').toString());
        if (date == null) continue;
        daily.add(
          AdminDailyActive(
            date: date,
            activeGuardians: _int(item['activeGuardians']),
            activeChildren: _int(item['activeChildren']),
            recorded: item['recorded'] == true,
          ),
        );
      }
    }

    final jobs = <String, AdminJobStatus?>{};
    final rawJobs = json['jobs'];
    if (rawJobs is Map) {
      rawJobs.forEach((name, value) {
        jobs[name.toString()] = value is Map
            ? AdminJobStatus(
                ok: value['ok'] == true,
                lastRunAt: DateTime.tryParse(
                  (value['lastRunAt'] ?? '').toString(),
                )?.toLocal(),
              )
            : null;
      });
    }

    final server = json['server'];
    return AdminOverview(
      daily: daily,
      jobs: jobs,
      serverVersion:
          server is Map ? (server['version'] ?? '-').toString() : '-',
      runningSince: server is Map
          ? DateTime.tryParse((server['running_since'] ?? '').toString())
                ?.toLocal()
          : null,
    );
  }
}
