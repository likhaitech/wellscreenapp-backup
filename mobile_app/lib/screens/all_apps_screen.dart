import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/app_time_limit.dart';
import '../services/app_time_limit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_usage_icon.dart';
import '../widgets/wellscreen_bottom_nav.dart';
import 'device_pairing_screen.dart';
import 'profile_settings_screen.dart';
import 'reports_screen.dart';
import 'set_app_time_limit_dialog.dart';

/// Guardian-only screen, opened from the Parent Dashboard's "View All" action.
///
/// Data source: child_profiles/{childProfileId}.latestUsageReport.allApps
/// (falls back to topApps for older reports). The child's usage sync supplies
/// real installed application labels and icons, keyed by Android package name.
class AllAppsScreen extends StatefulWidget {
  const AllAppsScreen({super.key, required this.childProfileId});

  final String childProfileId;

  @override
  State<AllAppsScreen> createState() => _AllAppsScreenState();
}

class _AllAppsScreenState extends State<AllAppsScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _reportStream;
  Stream<List<AppTimeLimit>>? _limitsStream;
  final AppTimeLimitService _appTimeLimitService = AppTimeLimitService();

  @override
  void initState() {
    super.initState();
    _setReportStream();
  }

  @override
  void didUpdateWidget(covariant AllAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childProfileId != widget.childProfileId) {
      _setReportStream();
    }
  }

  void _setReportStream() {
    // An unpaired guardian has no child document to subscribe to.
    if (widget.childProfileId.isEmpty) {
      _reportStream = null;
      _limitsStream = null;
      return;
    }
    _reportStream = FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(widget.childProfileId)
        .snapshots();
    _limitsStream = _appTimeLimitService.watchLimits(widget.childProfileId);
  }

  void _openPeriodInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Previous days are not stored by the current child sync. '
          '7 Days, 30 Days, and Custom will be available once daily history is added.',
        ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    if (index == 0) {
      Navigator.pop(context);
    } else if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportsScreen(childProfileId: widget.childProfileId),
        ),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _reportStream,
          builder: (context, snapshot) {
            final report = snapshot.data?.data()?['latestUsageReport'];
            final reportMap = report is Map
                ? Map<String, dynamic>.from(report)
                : null;
            final apps = reportMap == null
                ? <_AppUsage>[]
                : _appsFromReport(reportMap);
            final recordedAt = _reportDate(reportMap, snapshot.data?.data());
            final now = DateTime.now();
            final isStale =
                recordedAt != null &&
                (recordedAt.year != now.year ||
                    recordedAt.month != now.month ||
                    recordedAt.day != now.day);
            final reportedMs =
                _nonnegativeInt(reportMap?['allAppsTotalUsageDurationMs']) ??
                _nonnegativeInt(reportMap?['totalUsageDurationMs']);
            // The report-level total covers the device's day. Use that when
            // present; only sum unique app durations if the total is missing.
            final totalMs =
                reportedMs ??
                apps.fold<int>(
                  0,
                  (runningTotal, app) => runningTotal + app.usageMs,
                );

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _pageHeader()),
                SliverToBoxAdapter(child: _periodSwitcher()),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _messageState(
                      Icons.cloud_off_rounded,
                      'Could not load app usage',
                      'Please check your connection and try again.\n${snapshot.error}',
                    ),
                  )
                else if (widget.childProfileId.isEmpty || reportMap == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _messageState(
                      Icons.phone_android_rounded,
                      'No usage report yet',
                      'Pair a child device and sync usage from the child app.',
                    ),
                  )
                else if (isStale)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _messageState(
                      Icons.event_busy_rounded,
                      'No usage report for today',
                      'The most recent report is from ${_formatDate(recordedAt)}. '
                          'Ask the child device to sync usage today.',
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: _summaryCard(
                      totalMs: totalMs,
                      appCount: apps.length,
                    ),
                  ),
                  if (apps.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _messageState(
                        Icons.apps_rounded,
                        'No apps used yet',
                        'Apps used today will appear after the child device syncs.',
                      ),
                    )
                  else
                    StreamBuilder<List<AppTimeLimit>>(
                      stream: _limitsStream,
                      builder: (context, limitSnapshot) {
                        final limitsByPackage = {
                          for (final rule
                              in limitSnapshot.data ?? <AppTimeLimit>[])
                            rule.packageName: rule,
                        };
                        return SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                          sliver: SliverList.builder(
                            itemCount: apps.length,
                            itemBuilder: (context, index) {
                              final app = apps[index];
                              return _appRow(
                                app,
                                limit: limitsByPackage[app.packageName],
                                first: index == 0,
                                last: index == apps.length - 1,
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ],
            );
          },
        ),
      ),
      // Reuses the existing WellScreen navigation widget and the same four
      // parent destinations. ReportsScreen itself is untouched.
      bottomNavigationBar: WellScreenBottomNav(
        currentIndex: 0,
        items: const [
          WellScreenNavItem(icon: Icons.home_rounded, label: 'Home'),
          WellScreenNavItem(
            icon: Icons.phone_android_rounded,
            label: 'Devices',
          ),
          WellScreenNavItem(icon: Icons.analytics_rounded, label: 'Reports'),
          WellScreenNavItem(icon: Icons.settings_rounded, label: 'Settings'),
        ],
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _pageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 18, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Back to Home',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              size: 28,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Apps',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'View all apps used by your child and their usage details.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodSwitcher() {
    const tabs = ['Today', '7 Days', '30 Days', 'Custom'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFDCE5F2)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i != 0)
                Container(width: 1, height: 16, color: const Color(0xFFE6EDF6)),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: i == 0 ? null : _openPeriodInfo,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      tabs[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: i == 0 ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({required int totalMs, required int appCount}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCEDFF9)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFD9E8FF),
            radius: 23,
            child: const Icon(
              Icons.phone_android_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Screen Time',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _durationLabel(totalMs),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 24,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 46, width: 1, color: const Color(0xFFCBD9EE)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Apps Used',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 3),
              Text(
                '$appCount',
                style: const TextStyle(
                  fontSize: 19,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appRow(
    _AppUsage app, {
    AppTimeLimit? limit,
    required bool first,
    required bool last,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(
        top: first ? const Radius.circular(19) : Radius.zero,
        bottom: last ? const Radius.circular(19) : Radius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAppDetails(app),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(
                children: [
                  _appIcon(app),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 12,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _metric(
                              Icons.access_time_rounded,
                              _durationLabel(app.usageMs),
                            ),
                            if (app.openCount != null)
                              _metric(
                                Icons.open_in_new_rounded,
                                '${app.openCount} times',
                              ),
                            if (app.averageDailyMs != null)
                              _metric(
                                Icons.calendar_today_rounded,
                                'Avg. ${_durationLabel(app.averageDailyMs!)}/day',
                              ),
                            if (app.lastUsed != null)
                              _metric(
                                Icons.history_rounded,
                                'Last ${_clockTime(app.lastUsed!)}',
                              ),
                          ],
                        ),
                        if (limit != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            'Daily limit: ${_durationLabel(limit.limitMilliseconds)}'
                            ' · Remaining: ${_durationLabel(limit.remainingMilliseconds(app.usageMs))}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          if (limit.limitReached(app.usageMs))
                            const Text(
                              'Limit reached · device enforcement not yet enabled',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.danger,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 21,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            if (!last)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Color(0xFFE9EFF7),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// The child's sync uploads the actual installed Android app icon as
  /// iconBase64. For older reports, show a neutral fallback without guessing
  /// the app identity from a package name or brand-specific asset.
  Widget _appIcon(_AppUsage app) {
    return AppUsageIcon(
      encoded: app.iconBase64,
      fallback: Icons.apps_rounded,
      fallbackColor: AppColors.primary,
    );
  }

  Future<void> _openTimeLimitEditor(_AppUsage app) async {
    // A stable Android package name is needed to apply the limit to the
    // correct application; a display name alone is not sufficient.
    if (widget.childProfileId.isEmpty || app.packageName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A paired child and app package are required.'),
        ),
      );
      return;
    }

    int? existingMinutes;
    try {
      existingMinutes = await _appTimeLimitService.readLimitMinutes(
        childProfileId: widget.childProfileId,
        packageName: app.packageName,
      );
    } catch (_) {
      // Firestore rules or temporary network errors may prevent the read.
      // Saving below will still surface a clear error if access is denied.
    }
    if (!mounted) return;

    final minutes = await showSetAppTimeLimitDialog(
      context: context,
      appName: app.displayName,
      usageTodayMs: app.usageMs,
      initialLimitMinutes: existingMinutes,
    );
    if (!mounted || minutes == null) return;

    try {
      await _appTimeLimitService.saveLimit(
        childProfileId: widget.childProfileId,
        packageName: app.packageName,
        appName: app.displayName,
        minutes: minutes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Daily limit saved. Automatic blocking requires child-device enforcement.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the limit: $e')));
    }
  }

  Future<void> _showAppDetails(_AppUsage app) async {
    final editLimit = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _appIcon(app),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Usage today: ${_durationLabel(app.usageMs)}'),
              if (app.openCount != null) Text('Times opened: ${app.openCount}'),
              if (app.averageDailyMs != null)
                Text('Average per day: ${_durationLabel(app.averageDailyMs!)}'),
              if (app.lastUsed != null)
                Text('Last used: ${_clockTime(app.lastUsed!)}'),
              const SizedBox(height: 10),
              Text(
                'Package: ${app.packageName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Set Time Limit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (editLimit == true && mounted) {
      await _openTimeLimitEditor(app);
    }
  }

  Widget _messageState(IconData icon, String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 44),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppUsage {
  _AppUsage({
    required this.packageName,
    required this.displayName,
    required this.usageMs,
    this.iconBase64,
    this.openCount,
    this.averageDailyMs,
    this.lastUsed,
  });

  final String packageName;
  final String displayName;
  final int usageMs;
  final String? iconBase64;
  final int? openCount;
  final int? averageDailyMs;
  final DateTime? lastUsed;

  factory _AppUsage.fromMap(Map<String, dynamic> raw) {
    final pkg = (raw['packageName'] ?? '').toString();
    final rawName = (raw['displayName'] ?? '').toString().trim();
    return _AppUsage(
      packageName: pkg,
      // A full package identifier is safer than a misleading last segment
      // (e.g. `orca` or `trill`) when an older usage report lacks a label.
      displayName: rawName.isNotEmpty
          ? rawName
          : (pkg.isNotEmpty ? pkg : 'Unknown App'),
      usageMs: _nonnegativeInt(raw['usageDurationMs']) ?? 0,
      iconBase64:
          raw['iconBase64'] is String &&
              (raw['iconBase64'] as String).isNotEmpty
          ? raw['iconBase64'] as String
          : null,
      // Optional forward-compatible fields. Current sync DOES NOT send them.
      openCount: _nonnegativeInt(raw['openCount']),
      averageDailyMs: _nonnegativeInt(raw['averageDailyUsageMs']),
      lastUsed: DateTime.tryParse((raw['lastTimeUsed'] ?? '').toString()),
    );
  }
}

List<_AppUsage> _appsFromReport(Map<String, dynamic> report) {
  // Prefer the uncapped synced list; older child clients supply topApps only.
  final rawList = report['allApps'] is List
      ? report['allApps']
      : report['topApps'];
  if (rawList is! List) return <_AppUsage>[];
  final unique = <String, _AppUsage>{};
  for (final raw in rawList) {
    if (raw is! Map) continue;
    final app = _AppUsage.fromMap(Map<String, dynamic>.from(raw));
    if (app.usageMs <= 0) continue;
    // Each entry represents a total for its package in the latest day's
    // snapshot. Never sum duplicates (that would double-count usage).
    final key = app.packageName.isNotEmpty
        ? app.packageName
        : 'name:${app.displayName.toLowerCase()}';
    final previous = unique[key];
    if (previous == null || app.usageMs > previous.usageMs) {
      unique[key] = app;
    }
  }
  return unique.values.toList()..sort((a, b) => b.usageMs.compareTo(a.usageMs));
}

int? _nonnegativeInt(dynamic value) {
  if (value is num && value.isFinite) return value < 0 ? 0 : value.toInt();
  return null;
}

DateTime? _reportDate(
  Map<String, dynamic>? report,
  Map<String, dynamic>? data,
) {
  final captured = report?['capturedAt'];
  if (captured is String) {
    final parsed = DateTime.tryParse(captured);
    if (parsed != null) return parsed.toLocal();
  }
  final updated = data?['usageReportUpdatedAt'];
  if (updated is Timestamp) return updated.toDate();
  return null;
}

String _durationLabel(int milliseconds) {
  final seconds = Duration(milliseconds: milliseconds).inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${seconds}s';
}

String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _clockTime(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}
