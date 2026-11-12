import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'pattern_detection_service.dart';

/// Sends only meaningful, de-duplicated usage incidents to the trusted backend.
///
/// The child cannot write the parent's inbox or dispatch FCM directly.
/// The backend verifies the paired child and uses stable event IDs to avoid
/// creating duplicate alerts on successive 5-minute usage synchronizations.
class MonitoringUsageAlertService {
  const MonitoringUsageAlertService();

  static String _dayStamp(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> reportUsage({
    required String childProfileId,
    required UsageReport report,
    required List<AppUsageSummary> appSummaries,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || childProfileId.isEmpty) return;

    final now = DateTime.now();
    final day = _dayStamp(now);
    final timestampMs = now.millisecondsSinceEpoch;

    // All app summaries, not the dashboard's top-ten subset.
    final usage = appSummaries.fold<Duration>(
      Duration.zero,
      (sum, app) => sum + app.usageDuration,
    );

    final lateNightActivity = appSummaries.any((app) {
      final lastUsed = app.lastTimeUsed;
      return lastUsed != null &&
          lastUsed.year == now.year &&
          lastUsed.month == now.month &&
          lastUsed.day == now.day &&
          (lastUsed.hour >= 22 || lastUsed.hour < 5);
    });

    final events = <Map<String, Object>>[];
    void add(String type, String eventId, String label) {
      events.add({
        'type': type,
        'eventId': eventId,
        'timestampMs': timestampMs,
        'subject': 'Device usage',
        'label': label,
      });
    }

    if (usage >= PatternDetectionService.warningTotalUsageLimit) {
      add('usage_warning_threshold', 'usage3h_$day', '3 hours today');
    }
    if (usage >= PatternDetectionService.unhealthyTotalUsageLimit) {
      add('usage_high_threshold', 'usage5h_$day', '5 hours today');
    }
    if (lateNightActivity) {
      add('late_night_usage', 'lateusage_$day', '10 PM–5 AM');
    }

    // Only use the catch-all unhealthy signal if none of the specific causes
    // above is available; otherwise it would duplicate an alert on the same
    // sync. PatternDetectionService also detects high-risk app patterns.
    if (events.isEmpty && report.patternStatus.name == 'unhealthy') {
      add(
        'unhealthy_usage_pattern',
        'unhealthy_$day',
        report.recommendationMessage,
      );
    }

    if (events.isEmpty) return;
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return;
      final result = await Dio().post<Object?>(
        '${AppConfig.backendBaseUrl}/monitoring/events',
        data: {
          'childProfileId': childProfileId,
          'events': events,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 40),
        ),
      );
      debugPrint('WellScreen usage monitoring dispatch: HTTP '
          '${result.statusCode}, events=${events.length}');
    } on DioException catch (error) {
      // A failed request is harmless to syncing or restriction enforcement.
      // Stable event IDs make retry-on-next-sync safe.
      debugPrint('WellScreen usage monitoring dispatch failed: '
          'HTTP=${error.response?.statusCode} '
          'detail=${error.response?.data ?? error.message}');
    } catch (error) {
      debugPrint('WellScreen usage monitoring dispatch error: $error');
    }
  }
}
