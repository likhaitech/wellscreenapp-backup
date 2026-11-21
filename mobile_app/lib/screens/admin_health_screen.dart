import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/admin_overview_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_activity_widgets.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';

/// Monitor System Health (view only).
///
/// Shows whether the server is reachable and which version is running,
/// the last run of each background job, recent errors and server updates.
/// The admin watches the system here; updates and bug fixes are made by
/// the developers and appear on this page by themselves.
class AdminHealthScreen extends StatefulWidget {
  const AdminHealthScreen({super.key, this.embedded = false, this.onViewLogs});

  /// True inside the admin dock (no app bar of its own).
  final bool embedded;

  /// Opens System logs (the Logs tab when embedded).
  final VoidCallback? onViewLogs;

  @override
  State<AdminHealthScreen> createState() => _AdminHealthScreenState();
}

class _AdminHealthScreenState extends State<AdminHealthScreen> {
  static const Set<String> _updateActions = {
    'server_updated',
    'server_patch_deployed', // older name of the same event
  };

  final AdminOverviewApiService _api = AdminOverviewApiService();

  bool _loading = true;
  bool _failed = false;
  AdminOverview? _overview;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    }).catchError((Object _) {});
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final overview = await _api.getOverview(days: 1);
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sinceLabel(DateTime? since) {
    if (since == null) return '';
    final hm = '${since.hour.toString().padLeft(2, '0')}:'
        '${since.minute.toString().padLeft(2, '0')}';
    return 'Running since ${adminDayLabel(since)} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          widget.embedded ? 4 : 8,
          16,
          widget.embedded ? kAdminDockClearance : 24,
        ),
        children: [
          if (widget.embedded) ...[
            const AdminPageTitle('System health'),
            const SizedBox(height: 14),
          ],
          _serverCard(),
          const SizedBox(height: 12),
          AdminJobHealthCard(
            jobs: _overview?.jobs ?? const {},
            loaded: _overview != null,
          ),
          const SizedBox(height: 12),
          _logCards(),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'This page is view only. App updates and bug fixes are made '
              'by the developers and show up here and in System logs.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WellScreenAppBar.subPage(title: 'System health'),
      body: body,
    );
  }

  Widget _serverCard() {
    final overview = _overview;
    final online = overview != null && !_failed;
    final status = adminServerStatus(
      loading: _loading,
      hasOverview: overview != null,
      failed: _failed,
    );
    final since = _sinceLabel(overview?.runningSince);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online ? AppColors.teal : AppColors.warningBg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Server version',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      overview?.serverVersion ?? '-',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (since.isNotEmpty)
                      Text(
                        since,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'App version',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    _appVersion ?? '-',
                    style: const TextStyle(
                      fontFamily: AppFonts.heading,
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_failed && !_loading) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _load,
              child: const Text(
                adminServerWakingMessage,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Recent errors and server updates from the last 200 system logs
  /// (filtered on the phone, so no extra Firestore index is needed).
  Widget _logCards() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        final logs = (snapshot.data?.docs ?? []).map((d) => d.data()).toList();
        final errors = logs
            .where((d) =>
                (d['level'] ?? '').toString().toLowerCase() == 'error')
            .take(5)
            .toList();
        final updates = logs
            .where((d) => _updateActions.contains(d['action']))
            .take(5)
            .toList();
        final loading = !snapshot.hasData && !snapshot.hasError;
        return Column(
          children: [
            _logCard(
              title: 'Recent errors',
              empty: snapshot.hasError
                  ? 'Unable to load errors.'
                  : (loading ? 'Loading...' : 'No errors recorded.'),
              entries: errors,
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              tint: AppColors.dangerBg,
              showAll: widget.onViewLogs,
            ),
            const SizedBox(height: 12),
            _logCard(
              title: 'Server updates',
              empty: snapshot.hasError
                  ? 'Unable to load updates.'
                  : (loading ? 'Loading...' : 'No server updates recorded.'),
              entries: updates,
              icon: Icons.cloud_done_outlined,
              color: AppColors.primary,
              tint: AppColors.primaryLight,
            ),
          ],
        );
      },
    );
  }

  Widget _logCard({
    required String title,
    required String empty,
    required List<Map<String, dynamic>> entries,
    required IconData icon,
    required Color color,
    required Color tint,
    VoidCallback? showAll,
  }) {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppFonts.heading,
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showAll != null)
                TextButton(onPressed: showAll, child: const Text('View logs')),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                empty,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final data in entries)
              _logRow(data, icon: icon, color: color, tint: tint),
        ],
      ),
    );
  }

  Widget _logRow(
    Map<String, dynamic> data, {
    required IconData icon,
    required Color color,
    required Color tint,
  }) {
    final when = [
      adminLogDay(data['timestamp']),
      adminLogTime(data['timestamp']),
    ].where((s) => s.isNotEmpty).join(' ');
    final details = data['details'];
    final version = details is Map ? details['version'] : null;
    final line = _updateActions.contains(data['action']) && version != null
        ? 'Version $version'
        : (data['message'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminActionTitle(data['action']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [line, when].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The server card's status word on System health.
String adminServerStatus({
  required bool loading,
  required bool hasOverview,
  required bool failed,
}) {
  if (loading && !hasOverview) return 'Checking';
  return hasOverview && !failed ? 'Online' : 'Not reachable';
}

const String adminServerWakingMessage =
    'The server may be waking up. Tap to try again.';
