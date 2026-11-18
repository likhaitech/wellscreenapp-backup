import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';

/// Reads and displays the rolling trace written by CaptureDebugLogger
/// (android/.../CaptureDebugLogger.kt) - an in-app-visible mirror of the
/// same WellScreenCapture logcat trace that WellScreenAccessibilityService
/// and BrowserUrlExtractor already log via Log.d.
///
/// WHY THIS SCREEN EXISTS: remote troubleshooting of a real detection bug
/// (browsing activity not being captured) repeatedly hit a wall getting
/// ADB/USB debugging recognized on the actual test device - `flutter
/// install` never listed the phone as a device at all, only
/// Windows/Chrome/Edge. Without logcat access there was no way to see
/// exactly where the capture pipeline was failing. This screen makes that
/// same trace readable directly on the phone, no computer or cable
/// required - open Chrome, navigate somewhere, then come back here and see
/// exactly which step (event received / view found / text extracted /
/// normalized / recorded) did or didn't happen.
///
/// Entries are stored under SharedPreferences key "capture_debug_log_json"
/// (the "flutter." prefix that Kotlin writes is stripped automatically on
/// the Dart side by the shared_preferences package - same pattern already
/// used for sms_alert_log_json, restriction_log_json, sync_log_json, and
/// browsing_log_json elsewhere in this app).
class CaptureDebugScreen extends StatefulWidget {
  const CaptureDebugScreen({super.key});

  @override
  State<CaptureDebugScreen> createState() => _CaptureDebugScreenState();
}

class _CaptureDebugScreenState extends State<CaptureDebugScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // This screen renders the RAW, un-normalized address-bar text captured
    // by BrowserUrlExtractor.kt (full URL incl. path/query, not just the
    // domain parents see in Reports) and it's reachable via an
    // undocumented long-press on child_home_screen.dart's logo - a gesture
    // with no auth check, only obscurity. That's fine for development
    // troubleshooting but must never load real captured data in a release
    // build, or the monitored child could read their own logged browsing
    // history straight out of the app meant to keep it from them.
    if (!kDebugMode) {
      _loading = false;
      return;
    }
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('capture_debug_log_json');
    setState(() {
      _entries = _decodeJsonList(raw).reversed.toList();
      _loading = false;
    });
  }

  Future<void> _clearLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('capture_debug_log_json', '[]');
    await _loadLog();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Debug log cleared.')),
    );
  }

  List<Map<String, dynamic>> _decodeJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _formatTimestamp(dynamic value) {
    if (value is! int) return 'Unknown time';
    final date = DateTime.fromMillisecondsSinceEpoch(value);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const WellScreenAppBar.subPage(title: 'Capture Debug Log'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'The capture debug log is only available in development '
              'builds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: WellScreenAppBar.subPage(
        title: 'Capture Debug Log',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadLog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: _entries.isEmpty ? null : _clearLog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLog,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          icon: Icons.bug_report_outlined,
                          iconColor: AppColors.info,
                          title: 'What is this?',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'A step-by-step trace of what the browsing-detection '
                          'service sees, written directly on this device. '
                          'Clear the log, open a browser and visit a site, then '
                          'pull down to refresh here - the newest entries show '
                          'exactly which step (event received, address bar '
                          'found, text extracted, domain recorded) did or '
                          "didn't happen.",
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_entries.isEmpty)
                    const AppEmptyState(
                      icon: Icons.hourglass_empty,
                      title: 'No entries yet',
                      message:
                          'Open a browser and visit a site, then pull down '
                          'to refresh. Nothing here means the accessibility '
                          'service is not receiving events at all yet - '
                          'double check Accessibility is still turned on for '
                          'WellScreen in Settings.',
                    )
                  else
                    ..._entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatTimestamp(entry['timestampMs']),
                                style: const TextStyle(
                                  color: AppColors.textDisabled,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (entry['message'] ?? '').toString(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
