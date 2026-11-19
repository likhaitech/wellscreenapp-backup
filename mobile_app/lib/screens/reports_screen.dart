import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/wellscreen_ui.dart';

import '../services/block_reason_label.dart';
import '../services/location_geocoding_service.dart';
import '../services/report_export_service.dart';
import '../services/sms_alert_label.dart';
import '../theme/app_theme.dart';
import 'gps_map_screen.dart';
import '../widgets/brand_app_icon.dart';

/// Small "All OK" / "N failed" status pill, shared by every log section on
/// the Alerts tab - lets a section's health be read from its collapsed
/// header alone (green vs. red, no scanning of the prose summary line
/// required), consistent with how AppBadge already flags risk level
/// elsewhere in this file (e.g. the AI Risk Assessment card above).
Widget _statusBadge({required int failedCount, String? okLabel}) {
  if (failedCount <= 0) {
    return AppBadge(
      label: okLabel ?? 'All OK',
      color: AppColors.success,
      background: AppColors.successBg,
      icon: Icons.check_circle_rounded,
    );
  }
  return AppBadge(
    label: '$failedCount failed',
    color: AppColors.danger,
    background: AppColors.dangerBg,
    icon: Icons.error_rounded,
  );
}

String _formatTimestamp(dynamic value) {
  DateTime? date;
  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is int) {
    date = DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (date == null) return 'Not available';
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours hour${hours == 1 ? '' : 's'} $minutes minute${minutes == 1 ? '' : 's'}';
  }
  if (minutes > 0) return '$minutes minute${minutes == 1 ? '' : 's'}';
  return '${duration.inSeconds} second${duration.inSeconds == 1 ? '' : 's'}';
}

List<Map<String, dynamic>> _decodeLog(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

/// One icon per detected category, so a flagged entry reads at a glance
/// instead of every flag looking like the same generic warning triangle.
IconData _categoryIcon(String? category) {
  switch (category) {
    case 'gambling':
      return Icons.casino_rounded;
    case 'drugs':
      return Icons.medication_rounded;
    case 'dangerous_material':
      return Icons.dangerous_rounded;
    case 'adult':
      return Icons.explicit_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}

/// Human-readable label for the raw category string the classifier stores
/// ('gambling'/'drugs'/'dangerous_material'/'adult'). Guardians see this
/// directly on the browsing activity badge - the raw snake_case value
/// (e.g. "dangerous_material") previously leaked straight into that badge
/// unchanged, which reads as an internal code, not something written for a
/// non-technical parent/guardian to understand at a glance.
String _categoryLabel(String? category) {
  switch (category) {
    case 'gambling':
      return 'Gambling';
    case 'drugs':
      return 'Drugs';
    case 'dangerous_material':
      return 'Dangerous Material';
    case 'adult':
      return 'Adult Content';
    default:
      return 'Flagged';
  }
}

/// Turns a raw Android package id into something a parent can read at a
/// glance, for the (hopefully rare) apps not covered by [_knownAppNames]
/// below. "com.zhiliaoapp.musically" -> "Musically" instead of the raw
/// id - trailing segments like "android"/"app" rarely add anything for a
/// parent and are dropped.
String _prettifyPackageName(String packageName) {
  final segments =
      packageName.split('.').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return packageName;
  const noise = {'android', 'app', 'mobile', 'lite', 'go', 'debug'};
  final candidate = segments.reversed.firstWhere(
    (s) => !noise.contains(s),
    orElse: () => segments.last,
  );
  final withSpaces = candidate.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  final words = withSpaces
      .split(RegExp(r'[_\-]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1));
  final label = words.join(' ');
  return label.isEmpty ? packageName : label;
}

/// Friendly names for the apps guardians are most likely to see flagged
/// (social, messaging, games) - covers the common case with a real app
/// name; anything else falls back to [_prettifyPackageName] instead of
/// showing the raw package id.
const Map<String, String> _knownAppNames = {
  'com.instagram.android': 'Instagram',
  'com.zhiliaoapp.musically': 'TikTok',
  'com.facebook.katana': 'Facebook',
  'com.facebook.orca': 'Messenger',
  'com.google.android.youtube': 'YouTube',
  'com.whatsapp': 'WhatsApp',
  'com.snapchat.android': 'Snapchat',
  'com.twitter.android': 'X (Twitter)',
  'com.discord': 'Discord',
  'com.android.chrome': 'Chrome',
  'com.reddit.frontpage': 'Reddit',
  'com.roblox.client': 'Roblox',
  'com.supercell.clashofclans': 'Clash of Clans',
  'com.mojang.minecraftpe': 'Minecraft',
  'com.spotify.music': 'Spotify',
  'com.netflix.mediaclient': 'Netflix',
  'com.google.android.gm': 'Gmail',
  'org.telegram.messenger': 'Telegram',
};

String _friendlyAppName(String? packageName) {
  if (packageName == null || packageName.isEmpty) return 'Unknown app';
  return _knownAppNames[packageName] ?? _prettifyPackageName(packageName);
}

/// Same idea as [_categoryLabel] above but for the other raw snake_case
/// values the alert logs store (alert types, etc.) - a fallback for
/// anything not covered by [_alertTypeLabel]'s named cases.
String _humanizeSnakeCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Human-readable label for the raw `alertType` a push-alert log entry
/// stores ('unhealthy_pattern'/'new_location'/etc.) - previously shown to
/// the parent unchanged, same problem [_categoryLabel] solves for
/// browsing categories.
String _alertTypeLabel(String? alertType) {
  switch (alertType) {
    case 'unhealthy_pattern':
      return 'Unhealthy usage pattern';
    case 'new_location':
      return 'New location shared';
    case 'restricted_app_blocked':
      return 'Restricted app blocked';
    default:
      return (alertType == null || alertType.isEmpty)
          ? 'Alert'
          : _humanizeSnakeCase(alertType);
  }
}

/// Reorders a log so entries needing attention surface first (most recent
/// first within each group), instead of a strict most-recent-first list
/// where a single failure from yesterday can be buried under five
/// successes from today. Used for the preview every [_ExpandableList]
/// shows before "Show all" is tapped, so the handful of items a parent
/// sees by default are the ones actually worth their attention.
List<Map<String, dynamic>> _prioritizeAttention(
  List<Map<String, dynamic>> log,
  bool Function(Map<String, dynamic> entry) isSuccess,
) {
  final needsAttention = log.where((e) => !isSuccess(e)).toList().reversed;
  final ok = log.where(isSuccess).toList().reversed;
  return [...needsAttention, ...ok];
}

/// A preview-then-expand list, used everywhere a log could grow past a
/// handful of entries (browsing activity, SMS/restriction/push/sync logs).
/// Shows [_previewCount] items with a "Show all N" toggle instead of
/// either silently truncating history or dumping a long list into the tab
/// all at once - it still scrolls normally with the rest of the tab
/// (there's no nested scroll view here), it just starts collapsed. Every
/// call site uses the same preview size, so it isn't exposed as a
/// constructor parameter (flutter analyze flags an optional parameter no
/// caller ever overrides as dead code).
class _ExpandableList extends StatefulWidget {
  const _ExpandableList({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  static const int _previewCount = 5;

  @override
  State<_ExpandableList> createState() => _ExpandableListState();
}

class _ExpandableListState extends State<_ExpandableList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.itemCount > _ExpandableList._previewCount;
    final visibleCount = _expanded
        ? widget.itemCount
        : _ExpandableList._previewCount.clamp(0, widget.itemCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visibleCount; i++) widget.itemBuilder(context, i),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded
                          ? 'Show less'
                          : 'Show all ${widget.itemCount}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A card whose body starts collapsed behind its header, showing only the
/// header and a one-line summary until tapped. Added because the Alerts
/// tab used to stack four always-open logs (SMS, restriction, push, sync)
/// one after another - each individually capped at a 5-item preview via
/// _ExpandableList, but all four fully visible at once still read as a
/// wall of raw log data on first glance. Tapping the header row expands
/// just that section; the summary line stays visible either way, so a
/// parent can tell at a glance whether anything needs attention without
/// opening every section.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.summary,
    required this.child,
    this.badge,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget summary;
  final Widget child;
  final bool initiallyExpanded;

  /// Optional status pill (built with AppBadge) shown next to the chevron
  /// - e.g. "All OK" / "1 failed" - so a section's health is readable
  /// without expanding it, instead of only the prose summary line below.
  final Widget? badge;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: () => setState(() => _expanded = !_expanded),
            child: AppSectionHeader(
              icon: widget.icon,
              iconColor: widget.iconColor,
              title: widget.title,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.badge != null) ...[
                    widget.badge!,
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          widget.summary,
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: widget.child,
            ),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

/// The ONE destination for "what's going on with my child's usage" -
/// everything that used to be split across UsageSummaryScreen, half of
/// AlertsReportsScreen, and (briefly, in an earlier pass of this redesign)
/// a separate bell-icon AlertsScreen now lives here as four selectable
/// tabs: Usage, Browsing, Location, Alerts. Reached from the bottom nav's
/// "Reports" tab, or from the bell icon (which deep-links straight to the
/// Alerts tab via [initialTab] instead of opening a second screen).
///
/// WHY EVERYTHING IS ONE SCREEN NOW, NOT TWO: the previous split (ongoing
/// state on the Reports tab vs discrete event logs on the bell) was a
/// reasonable taxonomy, but a parent looking for "what did the app catch"
/// still had to know which of two icons to tap - the exact kind of
/// discoverability problem this whole redesign started from. One screen
/// with visible, labeled tabs means everything is findable from a single
/// entry point, and switching between categories is one tap instead of a
/// full navigation.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.childProfileId,
    this.initialTab = 0,
  });

  final String childProfileId;

  /// 0 = Usage, 1 = Browsing, 2 = Location, 3 = Alerts. The bell icon in
  /// parent_dashboard_screen.dart passes 3 so it lands directly on Alerts
  /// instead of making the parent re-select it.
  final int initialTab;

  static const List<Tab> _tabs = [
    Tab(text: 'Usage'),
    Tab(text: 'Browsing'),
    Tab(text: 'Location'),
    Tab(text: 'Alerts'),
  ];

  @override
  Widget build(BuildContext context) {
    if (childProfileId.isEmpty) {
      return Scaffold(
        appBar: const WellScreenAppBar.subPage(title: 'Reports'),
        body: const _ReportsEmptyState(
          message: 'Pair a child device first to see reports.',
        ),
      );
    }

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WellScreenAppBar.subPage(
                title: 'Reports',
                actions: [
                  AppPillButton(
                    label: 'Export PDF',
                    compact: true,
                    onPressed: () => _exportReport(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              // Category pills: the active one is a filled blue pill, the
              // others are plain labels.
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  // Design D: light indigo track, selected tab is a white pill.
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: TabBar(
                    tabs: _tabs,
                    dividerColor: Colors.transparent,
                    splashBorderRadius: BorderRadius.circular(AppRadius.pill),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: EdgeInsets.zero,
                    indicator: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    labelPadding: EdgeInsets.zero,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('child_profiles')
              .doc(childProfileId)
              .snapshots(),
          builder: (context, snapshot) {
            // Previously missing: without this check, a genuine Firestore
            // read failure (permission error, network issue) fell straight
            // through to `snapshot.data?.data() ?? {}`, which every tab
            // below then renders identically to "nothing has synced yet" -
            // actively misleading, since a parent (or a panelist during a
            // demo) has no way to tell a real backend failure apart from a
            // child device that just hasn't reported in yet.
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppErrorState(
                    title: 'Could Not Load Reports',
                    message: 'Something went wrong loading this child\'s '
                        'reports.\n\n${snapshot.error}',
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: AppSpacing.md),
                    Text(
                      'Loading reports...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data?.data() ?? <String, dynamic>{};

            return TabBarView(
              children: [
                _usageTab(context, data),
                _browsingTab(context, data),
                _locationTab(context, data),
                _alertsTab(context, data),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Builds a PDF snapshot of this child's current report data (via
  /// [ReportExportService], which does its own one-off Firestore read
  /// rather than reusing this screen's live stream - see that service's
  /// class doc comment) and opens the platform share sheet on it.
  Future<void> _exportReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generating report...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await ReportExportService.exportChildReport(childProfileId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to export report: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Usage tab - today's screen time, top apps, detected pattern, AI risk.
  // ---------------------------------------------------------------------

  Widget _usageTab(BuildContext context, Map<String, dynamic> data) {
    final report = data['latestUsageReport'];
    final mlRiskAssessment = data['mlRiskAssessment'];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (report is Map)
          _usageSummarySection(
            context,
            Map<String, dynamic>.from(report),
            data['usageReportUpdatedAt'],
          )
        else
          const AppEmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'Today\'s Usage',
            message: 'No usage data synced yet. Ask your child to open '
                'WellScreen and tap "Sync Usage".',
          ),
        if (report is Map)
          _usagePatternCard(context, Map<String, dynamic>.from(report)),
        if (mlRiskAssessment is Map)
          _mlRiskAssessmentCard(
            context,
            Map<String, dynamic>.from(mlRiskAssessment),
          )
        else
          const AppEmptyState(
            icon: Icons.psychology_alt_rounded,
            title: 'AI Risk Assessment',
            message: 'Not synced yet - runs automatically the next time '
                'usage data is synced.',
          ),
      ],
    );
  }

  Widget _usageSummarySection(
    BuildContext context,
    Map<String, dynamic> report,
    dynamic updatedAt,
  ) {
    final totalMs = report['totalUsageDurationMs'];
    final totalDuration =
        totalMs is num ? Duration(milliseconds: totalMs.toInt()) : Duration.zero;

    final rawApps = report['topApps'];
    final apps = rawApps is List
        ? rawApps
            .whereType<Map>()
            .map((app) => Map<String, dynamic>.from(app))
            .toList()
        : <Map<String, dynamic>>[];
    final topAppNames = apps
        .take(3)
        .map((app) => (app['displayName'] ?? app['packageName'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .join(', ');
    final unhealthyCount = report['unhealthyAppCount'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.today_rounded,
            iconColor: AppColors.primary,
            title: 'Today\'s Screen Time',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _formatDuration(totalDuration),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 22, color: AppColors.primary),
          ),
          Text(
            'Last synced ${_formatTimestamp(updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Divider(height: AppSpacing.xl),
          Text('Top Used Applications',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            topAppNames.isEmpty ? 'No app usage recorded today' : topAppNames,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Apps Needing Attention',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${unhealthyCount is num ? unhealthyCount.toInt() : 0} app(s) '
            'flagged for unhealthy usage today.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _usagePatternCard(BuildContext context, Map<String, dynamic> report) {
    final status = (report['patternStatus'] ?? 'healthy').toString();
    final recommendation =
        (report['recommendationMessage'] ?? 'No recommendation available.')
            .toString();

    final (icon, color, bg, title) = switch (status) {
      'unhealthy' => (
          Icons.warning_amber_rounded,
          AppColors.danger,
          AppColors.dangerBg,
          'Unhealthy Usage Pattern',
        ),
      'warning' => (
          Icons.shield_moon_rounded,
          AppColors.warning,
          AppColors.warningBg,
          'Usage Warning',
        ),
      _ => (
          Icons.check_circle_rounded,
          AppColors.success,
          AppColors.successBg,
          'Healthy Usage Pattern',
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: icon,
            iconColor: color,
            title: 'Detected Pattern',
            trailing: AppBadge(label: title, color: color, background: bg),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(recommendation, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _mlRiskAssessmentCard(
    BuildContext context,
    Map<String, dynamic> assessment,
  ) {
    final label = (assessment['label'] ?? 'Unknown').toString();
    final confidence = assessment['confidence'];
    final confidencePercent =
        confidence is num ? (confidence * 100).toStringAsFixed(0) : null;

    final (icon, color, bg) = switch (label) {
      'High Risk' => (
          Icons.warning_amber_rounded,
          AppColors.danger,
          AppColors.dangerBg,
        ),
      'Moderate Risk' => (
          Icons.shield_moon_rounded,
          AppColors.warning,
          AppColors.warningBg,
        ),
      _ => (
          Icons.check_circle_rounded,
          AppColors.success,
          AppColors.successBg,
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.psychology_alt_rounded,
            iconColor: AppColors.accent,
            title: 'AI Risk Assessment',
            trailing: AppBadge(
              label: confidencePercent != null ? '$label $confidencePercent%' : label,
              color: color,
              background: bg,
              icon: icon,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'WellScreen\'s AI assistant (Random Forest, on the child\'s '
            'phone) estimates today\'s usage risk '
            'from activity patterns. It supplements the usage pattern '
            'summary above - it is not a medical or diagnostic assessment, '
            'and should not be used on its own.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Browsing tab - captured domains and how category detection works.
  // ---------------------------------------------------------------------

  Widget _browsingTab(BuildContext context, Map<String, dynamic> data) {
    final browsingLog = _decodeLog(data['browsingLog']);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _BrowsingActivityCard(log: browsingLog),
        _categoryDetectionInfoCard(context),
      ],
    );
  }

  Widget _categoryDetectionInfoCard(BuildContext context) {
    return _CollapsibleSection(
      icon: Icons.category_rounded,
      iconColor: AppColors.primary,
      title: 'How Category Detection Works',
      summary: Text(
        'Tap to see how flagged sites are detected.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      child: Text(
        'WellScreen checks browsing activity three ways, entirely on '
        'the child\'s device: an exact match against a large, curated '
        'list of known harmful sites (gambling, drugs, dangerous '
        'items, and adult content), a keyword check for explicit '
        'content, and an AI model that catches gambling sites not yet '
        'on the list.\n\n'
        'This is detection and after-the-fact alerting, not blocking '
        '- a flagged page will still have loaded on the child\'s '
        'device before you see the alert here, since real-time '
        'blocking isn\'t built yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Location tab.
  // ---------------------------------------------------------------------

  Widget _locationTab(BuildContext context, Map<String, dynamic> data) {
    final location = data['latestLocation'];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (location is Map)
          _LocationTabCard(
            location: Map<String, dynamic>.from(location),
            updatedAt: data['locationUpdatedAt'],
          )
        else
          const AppEmptyState(
            icon: Icons.location_on_rounded,
            title: 'Location Update',
            message: 'No GPS location shared yet.',
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Alerts tab - discrete things that already happened (SMS sent, an app
  // blocked, a push delivered, a sync attempt). Moved here from the bell
  // icon's old standalone AlertsScreen - see this file's class doc comment
  // for why. The bell now just deep-links to this tab via [initialTab].
  // ---------------------------------------------------------------------

  Widget _alertsTab(BuildContext context, Map<String, dynamic> data) {
    final smsLog = _decodeLog(data['smsAlertLog']);
    final restrictionLog = _decodeLog(data['restrictionLog']);
    final pushAlertLog = _decodeLog(data['pushAlertLog']);
    final syncLog = _decodeLog(data['syncLog']);

    final smsFailed = smsLog
        .where((e) => (e['outcome'] as String? ?? '').startsWith('failed'))
        .length;
    // "blocked" is the normal enforcement outcome; a parent-approved
    // emergency-access bypass is also a correctly-working outcome, not a
    // failure - matches the isSuccess check passed to _logSummarySection
    // below so this summary count and that section's per-entry badges and
    // sort-to-top-when-failing behavior agree with each other.
    final restrictionFailed = restrictionLog
        .where(
          (e) =>
              e['outcome'] != 'blocked' &&
              e['outcome'] != 'emergency_access_bypass',
        )
        .length;
    final pushFailed = pushAlertLog.where((e) => e['outcome'] != 'sent').length;
    final syncFailed = syncLog.where((e) => e['outcome'] != 'synced').length;

    final totalEvents =
        smsLog.length + restrictionLog.length + pushAlertLog.length + syncLog.length;
    final totalFailed = smsFailed + restrictionFailed + pushFailed + syncFailed;

    // Each section paired with its failure count (and original position,
    // so ties keep the usual SMS/Restriction/Push/Sync order - List.sort
    // isn't guaranteed stable) so sections needing attention can float to
    // the top instead of a parent scrolling past three "All OK" cards to
    // find the one that failed.
    final sections = <(int failed, int order, Widget card)>[
      (smsFailed, 0, _smsAlertSection(context, smsLog)),
      (
        restrictionFailed,
        1,
        _logSummarySection(
          context,
          log: restrictionLog,
          icon: Icons.block_rounded,
          iconColor: AppColors.danger,
          title: 'Restriction Enforcement',
          emptyMessage: 'No restricted-app blocks recorded yet on the '
              'child device.',
          // "blocked" is the normal enforcement outcome; an emergency-access
          // bypass is also a correctly-working outcome (the parent approved
          // it), not a failure, so both read as success-styled here - only
          // an actual failed_exception should show as a failure.
          isSuccess: (entry) =>
              entry['outcome'] == 'blocked' ||
              entry['outcome'] == 'emergency_access_bypass',
          entryLabel: (entry) {
            final reason = blockReasonLabel(entry);
            return '${_friendlyAppName(entry['packageName'] as String?)} · '
                '${entry['outcome'] ?? 'unknown'}'
                '${reason == null ? '' : ' · $reason'}';
          },
        ),
      ),
      (
        pushFailed,
        2,
        _logSummarySection(
          context,
          log: pushAlertLog,
          icon: Icons.notifications_active_rounded,
          iconColor: AppColors.info,
          title: 'Push Notification Delivery',
          emptyMessage: 'No push notifications sent yet. These fire '
              'automatically when an unhealthy usage pattern is detected '
              'or a new location is shared.',
          isSuccess: (entry) => entry['outcome'] == 'sent',
          entryLabel: (entry) =>
              '${_alertTypeLabel(entry['alertType'] as String?)} · '
              '${entry['outcome'] ?? 'unknown'}',
        ),
      ),
      (
        syncFailed,
        3,
        _logSummarySection(
          context,
          log: syncLog,
          icon: Icons.sync_rounded,
          iconColor: AppColors.accent,
          title: 'Synchronization Status',
          emptyMessage: 'No sync attempts recorded yet - this tracks '
              'whether "Sync Usage" actually reached the server, including '
              'automatic retries after being offline.',
          isSuccess: (entry) => entry['outcome'] == 'synced',
          entryLabel: (entry) {
            final trigger = entry['trigger'] == 'auto_reconnect'
                ? 'Reconnected automatically'
                : 'Manual sync';
            final recovery = entry['recoveryTimeMs'];
            String recoverySuffix = '';
            if (recovery is num) {
              recoverySuffix = recovery >= 1000
                  ? ' · back online in ${(recovery / 1000).toStringAsFixed(1)}s'
                  : ' · back online in ${recovery.toInt()}ms';
            }
            return '$trigger · '
                '${entry['outcome'] ?? 'unknown'}$recoverySuffix';
          },
        ),
      ),
    ]..sort((a, b) {
        final byFailed = b.$1.compareTo(a.$1);
        return byFailed != 0 ? byFailed : a.$2.compareTo(b.$2);
      });

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (totalEvents > 0) ...[
          _alertsHeroBanner(totalEvents: totalEvents, totalFailed: totalFailed),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final section in sections) section.$3,
      ],
    );
  }

  /// A gradient at-a-glance summary at the top of the Alerts tab -
  /// mirrors the "Child Location" hero banner style already used on the
  /// full GPS Map View screen (gps_map_screen.dart), so the same visual
  /// language shows up here instead of the tab opening straight into raw
  /// log cards. Reframes "here are four logs" as "here's your status,
  /// drill in if you want detail."
  Widget _alertsHeroBanner({
    required int totalEvents,
    required int totalFailed,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalEvents event${totalEvents == 1 ? '' : 's'} logged',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalFailed == 0
                      ? 'Everything is working as expected.'
                      : '$totalFailed need${totalFailed == 1 ? 's' : ''} a '
                          'closer look.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Real SMS backup-alert delivery log, synced from the child device's
  /// local record of what SmsSentReceiver/SmsDeliveredReceiver actually
  /// observed (see SmsAlertSender.kt) - not a simulated success rate.
  Widget _smsAlertSection(
    BuildContext context,
    List<Map<String, dynamic>> smsLog,
  ) {
    if (smsLog.isEmpty) {
      return const AppEmptyState(
        icon: Icons.sms_rounded,
        title: 'SMS Backup Alerts',
        message: 'No SMS alerts sent yet. These are sent automatically when a '
            'restricted app is blocked on the child device (if SMS '
            'permission is granted and a parent phone number is set).',
      );
    }

    final sentOrDelivered = smsLog
        .where((entry) =>
            entry['outcome'] == 'sent' || entry['outcome'] == 'delivered')
        .length;
    final failed = smsLog
        .where((entry) =>
            (entry['outcome'] as String? ?? '').startsWith('failed'))
        .length;
    bool isSuccess(Map<String, dynamic> entry) =>
        smsAlertSucceeded(entry['outcome'] as String?);

    final ordered = _prioritizeAttention(smsLog, isSuccess);

    String entryLabel(Map<String, dynamic> entry) =>
        '${_friendlyAppName(entry['packageName'] as String?)} · '
        '${smsAlertOutcomeLabel(entry['outcome'] as String?)}';

    return _CollapsibleSection(
      // Alerts-tab sections now reorder by failure count (see _alertsTab),
      // so each needs a stable key - otherwise Flutter matches widget
      // state by list position and a section's expand/collapse state (or
      // the "All/Flagged only" filter on browsing) could leak onto a
      // different section after a reorder.
      key: const ValueKey('SMS Backup Alerts'),
      icon: Icons.sms_rounded,
      iconColor: AppColors.primary,
      title: 'SMS Backup Alerts',
      badge: _statusBadge(failedCount: failed),
      initiallyExpanded: failed > 0,
      summary: Text(
        '$sentOrDelivered sent/delivered, $failed failed, out of '
        '${smsLog.length} attempt${smsLog.length == 1 ? '' : 's'} '
        '(most recent ${smsLog.length > 50 ? 50 : smsLog.length} kept '
        'on device).',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      child: _ExpandableList(
        itemCount: ordered.length,
        itemBuilder: (context, i) => _entryRow(
          context,
          ordered[i],
          isSuccess: isSuccess(ordered[i]),
          label: entryLabel(ordered[i]),
        ),
      ),
    );
  }

  /// Generic outcome-log card shared by restriction-enforcement,
  /// push-notification-delivery, and sync sections (all the same shape: a
  /// list of {outcome, responseTimeMs, timestampMs, ...} entries recorded
  /// natively/client-side at the moment each attempt happened, not
  /// simulated).
  Widget _logSummarySection(
    BuildContext context, {
    required List<Map<String, dynamic>> log,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String emptyMessage,
    required bool Function(Map<String, dynamic> entry) isSuccess,
    required String Function(Map<String, dynamic> entry) entryLabel,
  }) {
    if (log.isEmpty) {
      return AppEmptyState(icon: icon, title: title, message: emptyMessage);
    }

    final successCount = log.where(isSuccess).length;
    final failedCount = log.length - successCount;
    final responseTimes = log
        .map((entry) => entry['responseTimeMs'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final avgResponseMs = responseTimes.isEmpty
        ? null
        : (responseTimes.reduce((a, b) => a + b) / responseTimes.length)
            .round();
    final ordered = _prioritizeAttention(log, isSuccess);

    return _CollapsibleSection(
      // See the matching comment in _smsAlertSection - this section can
      // also change position in the Alerts tab, so it needs a stable key.
      key: ValueKey(title),
      icon: icon,
      iconColor: iconColor,
      title: title,
      badge: _statusBadge(failedCount: failedCount),
      initiallyExpanded: failedCount > 0,
      summary: Text(
        '$successCount succeeded, $failedCount failed, out of '
        '${log.length} attempt${log.length == 1 ? '' : 's'}'
        '${avgResponseMs != null ? ' · avg response time ${avgResponseMs}ms' : ''}.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      child: _ExpandableList(
        itemCount: ordered.length,
        itemBuilder: (context, i) => _entryRow(
          context,
          ordered[i],
          isSuccess: isSuccess(ordered[i]),
          label: entryLabel(ordered[i]),
        ),
      ),
    );
  }

  /// One log-entry row, shared by the SMS, restriction, push, and sync
  /// sections above - all render the same shape (success/fail icon + a
  /// one-line label + timestamp), just built from different fields.
  Widget _entryRow(
    BuildContext context,
    Map<String, dynamic> entry, {
    required bool isSuccess,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: isSuccess ? AppColors.success : AppColors.danger,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$label · ${_formatTimestamp(entry['timestampMs'])}',
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Location tab's main card. Previously just a text line with the raw
/// label/coordinates and a "Last synced" timestamp - no map at all, even
/// though the parent dashboard's GPS card and the full GPS Map View screen
/// both already had one. Now shows the same small static map preview used
/// on the dashboard (GpsMapPreview, from gps_map_screen.dart) plus a
/// reverse-geocoded place name (LocationGeocodingService - the same
/// service wired into the full GPS Map View) so "where is my child" is
/// answerable without leaving this tab. "View Full Map" still opens the
/// interactive GpsMapScreen for panning/zooming. Stateful for the same
/// reason _BrowsingActivityCard is: it needs to hold the in-flight
/// reverse-geocode result without threading that state up into
/// ReportsScreen itself.
class _LocationTabCard extends StatefulWidget {
  const _LocationTabCard({required this.location, required this.updatedAt});

  final Map<String, dynamic> location;
  final dynamic updatedAt;

  @override
  State<_LocationTabCard> createState() => _LocationTabCardState();
}

class _LocationTabCardState extends State<_LocationTabCard> {
  final LocationGeocodingService _geocodingService =
      LocationGeocodingService();

  bool _isResolvingAddress = true;
  String? _resolvedPlaceName;

  double get _latitude {
    final value = widget.location['latitude'];
    return value is num ? value.toDouble() : 0;
  }

  double get _longitude {
    final value = widget.location['longitude'];
    return value is num ? value.toDouble() : 0;
  }

  bool get _hasCoordinates =>
      widget.location['latitude'] is num && widget.location['longitude'] is num;

  String get _fallbackLabel {
    final label = widget.location['label'];
    if (label != null && label.toString().isNotEmpty) return label.toString();
    if (_hasCoordinates) {
      return '${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}';
    }
    return 'No shared GPS yet';
  }

  @override
  void initState() {
    super.initState();
    if (_hasCoordinates) {
      _resolveAddress();
    } else {
      _isResolvingAddress = false;
    }
  }

  @override
  void didUpdateWidget(covariant _LocationTabCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasCoordinates &&
        (oldWidget.location['latitude'] != widget.location['latitude'] ||
            oldWidget.location['longitude'] != widget.location['longitude'])) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    setState(() {
      _isResolvingAddress = true;
      _resolvedPlaceName = null;
    });

    final placeName = await _geocodingService.reverseGeocode(
      latitude: _latitude,
      longitude: _longitude,
    );

    if (!mounted) return;

    setState(() {
      _resolvedPlaceName = placeName;
      _isResolvingAddress = false;
    });
  }

  String get _placeNameText {
    if (_isResolvingAddress) return 'Locating address...';
    return _resolvedPlaceName ?? _fallbackLabel;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.location_on_rounded,
            iconColor: AppColors.success,
            title: 'Location Update',
            trailing: _hasCoordinates
                ? const AppBadge(
                    label: 'Shared',
                    color: AppColors.success,
                    background: AppColors.successBg,
                    icon: Icons.check_circle_rounded,
                  )
                : const AppBadge(
                    label: 'No GPS yet',
                    color: AppColors.textSecondary,
                    background: AppColors.background,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_hasCoordinates) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card - 4),
              child: GpsMapPreview(
                latitude: _latitude,
                longitude: _longitude,
                hasLocation: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _isResolvingAddress
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.place_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _placeNameText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last synced: ${_formatTimestamp(widget.updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (_hasCoordinates) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GpsMapScreen(
                        latitude: _latitude,
                        longitude: _longitude,
                        label: _fallbackLabel,
                        updatedAt: _formatTimestamp(widget.updatedAt),
                        hasLocation: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('View Full Map'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Real domains captured natively by BrowserUrlExtractor/BrowsingLogger,
/// then classified against the real UT1 dataset by SiteCategoryService in
/// syncUsageReport() - entries with a 'category' key matched the dataset
/// (or the keyword/ML fallback) and triggered a parent alert. Stateful (not
/// a plain method like the rest of this screen) so it can hold its own
/// "All / Flagged only" filter and remember whether the list is expanded
/// without threading that state up into ReportsScreen itself.
class _BrowsingActivityCard extends StatefulWidget {
  const _BrowsingActivityCard({required this.log});

  final List<Map<String, dynamic>> log;

  @override
  State<_BrowsingActivityCard> createState() => _BrowsingActivityCardState();
}

class _BrowsingActivityCardState extends State<_BrowsingActivityCard> {
  bool _flaggedOnly = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;

    if (log.isEmpty) {
      return const AppEmptyState(
        icon: Icons.public_rounded,
        title: 'Recent Browsing Activity',
        message: 'No browser domains captured yet - requires WellScreen\'s '
            'Accessibility permission and one of the supported browsers '
            '(Chrome, Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) '
            'to be used on the child device.',
      );
    }

    final flaggedCount = log.where((e) => e['category'] != null).length;
    final reversed = log.reversed.toList();
    final visible = _flaggedOnly
        ? reversed.where((e) => e['category'] != null).toList()
        : reversed;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.public_rounded,
            iconColor: AppColors.primary,
            title: 'Recent Browsing Activity',
            trailing: flaggedCount > 0
                ? AppBadge(
                    label: '$flaggedCount flagged',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                    icon: Icons.flag_rounded,
                  )
                : const AppBadge(
                    label: 'All clear',
                    color: AppColors.success,
                    background: AppColors.successBg,
                    icon: Icons.check_circle_rounded,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${log.length} domain${log.length == 1 ? '' : 's'} captured. '
            '${flaggedCount > 0 ? '$flaggedCount flagged by category matching.' : 'None matched a harmful category.'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (flaggedCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _filterChip(
                  label: 'All (${log.length})',
                  selected: !_flaggedOnly,
                  onTap: () => setState(() => _flaggedOnly = false),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Flagged only ($flaggedCount)',
                  selected: _flaggedOnly,
                  onTap: () => setState(() => _flaggedOnly = true),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (visible.isEmpty)
            const Text(
              'No flagged domains yet.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            _ExpandableList(
              itemCount: visible.length,
              itemBuilder: (context, i) => _entry(context, visible[i]),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, Map<String, dynamic> entry) {
    final category = entry['category'];
    final source = entry['detectionSource'];
    final (sourceLabel, sourceColor) = switch (source) {
      'ml' => ('AI-detected', AppColors.sourceMl),
      'keyword' => ('keyword match', AppColors.sourceKeyword),
      _ => ('exact match', AppColors.sourceLookup),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flagged (harmful) sites keep a warning icon - their own logos
          // are not loaded into the guardian's report. Other sites show
          // their real icon.
          if (category != null)
            Icon(_categoryIcon(category), color: AppColors.danger, size: 16)
          else
            BrandAppIcon(
              label: (entry['domain'] ?? '?').toString(),
              domain: (entry['domain'] ?? '').toString(),
              size: 24,
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (entry['domain'] ?? 'unknown domain').toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        category != null ? FontWeight.w700 : FontWeight.w500,
                    color: category != null
                        ? AppColors.danger
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  _formatTimestamp(entry['timestampMs']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (category != null)
            AppBadge(
              label: '${_categoryLabel(category as String?)} · $sourceLabel',
              color: sourceColor,
              background: sourceColor.withValues(alpha: 0.12),
            ),
        ],
      ),
    );
  }
}

class _ReportsEmptyState extends StatelessWidget {
  const _ReportsEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: AppColors.textDisabled, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
