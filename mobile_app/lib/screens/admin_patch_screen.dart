import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../services/app_release_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';

/// Monitor System Patches (view only).
///
/// Patches and fixes are applied on the backend, never from the app: a
/// code fix is pushed and Render redeploys (logged as "Server patch
/// deployed"), and a settings patch - minimum app version or maintenance
/// notice - is a reviewed JSON file applied with the backend patch tool
/// (backend/scripts/apply_system_patch.py), which validates it and logs
/// it as applied or rejected. This page shows what is running now and the
/// patch history so the admin can confirm a patch landed.
class AdminPatchScreen extends StatefulWidget {
  const AdminPatchScreen({super.key, this.embedded = false});

  /// True inside the admin dock (no app bar of its own).
  final bool embedded;

  @override
  State<AdminPatchScreen> createState() => _AdminPatchScreenState();
}

class _AdminPatchScreenState extends State<AdminPatchScreen> {
  static const Set<String> _historyActions = {
    'server_patch_deployed',
    'system_patch_applied',
    'system_patch_rejected',
  };

  final AdminSettingsApiService _api = AdminSettingsApiService();

  bool _loading = true;
  String? _loadError;
  String _serverVersion = '-';
  String? _runningSince;
  String _currentMinimum = '1.0.0';
  String _currentNotice = '';
  String? _thisAppVersion;

  @override
  void initState() {
    super.initState();
    AppReleaseService.installedVersion().then((v) {
      if (mounted) setState(() => _thisAppVersion = v);
    }).catchError((Object _) {});
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await _api.getSettings();
      final server = settings['server'];
      final minimum = settings['minimum_app_version'];
      final notice = settings['maintenance_message'];
      _serverVersion =
          server is Map ? (server['version'] ?? '-').toString() : '-';
      _runningSince =
          server is Map ? server['running_since']?.toString() : null;
      _currentMinimum = minimum is String ? minimum : '1.0.0';
      _currentNotice = notice is String ? notice : '';
    } catch (e) {
      _loadError = 'Could not load the current settings. The server may be '
          'waking up - try again in a minute.';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _sinceLabel() {
    final since = DateTime.tryParse(_runningSince ?? '')?.toLocal();
    if (since == null) return '';
    final hm = '${since.hour.toString().padLeft(2, '0')}:'
        '${since.minute.toString().padLeft(2, '0')}';
    return 'Running since ${since.month}/${since.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
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
                  const AdminPageTitle('System patch'),
                  const SizedBox(height: 14),
                ],
                if (_loadError != null) ...[
                  _resultCard(
                    icon: Icons.cloud_off_rounded,
                    color: AppColors.warning,
                    tint: AppColors.warningBg,
                    title: _loadError!,
                    lines: const [],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ] else ...[
                  _versionCard(),
                  const SizedBox(height: 12),
                  _settingsCard(),
                ],
                const SizedBox(height: 12),
                _resultCard(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.primary,
                  tint: AppColors.primaryLight,
                  title: 'Patches are applied on the backend',
                  lines: const [
                    'Code fixes are deployed to the server and recorded '
                        'here as "Server patch deployed".',
                    'Settings patches are reviewed files applied with the '
                        'backend patch tool. Every patch is checked first; '
                        'a rejected patch changes nothing.',
                    'This page is view only, so the app cannot change the '
                        'system.',
                  ],
                ),
                const SizedBox(height: 18),
                const AdminSectionTitle('Patch history'),
                const SizedBox(height: 8),
                _history(),
              ],
            ),
          );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: WellScreenAppBar.subPage(
        title: 'System patch',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _versionCard() {
    final since = _sinceLabel();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Server version',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _serverVersion,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (since.isNotEmpty)
                  Text(
                    since,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'This app',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _thisAppVersion ?? '-',
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
    );
  }

  Widget _settingsCard() {
    final thisApp = _thisAppVersion;
    final mustUpdate = thisApp != null &&
        AppReleaseService.isVersion(_currentMinimum) &&
        AppReleaseService.needsUpdate(thisApp, _currentMinimum);
    return BentoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _settingRow(
            icon: Icons.system_update_outlined,
            title: 'Minimum app version',
            value: _currentMinimum,
            note: mustUpdate
                ? 'Phones on $thisApp must update to continue.'
                : 'Phones below this version must update first.',
          ),
          const Divider(height: 1, color: AppColors.surfaceMuted),
          _settingRow(
            icon: Icons.campaign_outlined,
            title: 'Maintenance notice',
            value: _currentNotice.isEmpty ? 'None' : 'On',
            note: _currentNotice.isEmpty
                ? 'No notice is shown to guardians and children.'
                : _currentNotice,
          ),
        ],
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String value,
    required String note,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.violetBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.violet, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: AppFonts.heading,
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Deploys and patches from the last 100 system logs (filtered on the
  /// phone, so no extra Firestore index is needed).
  Widget _history() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Unable to load the patch history.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        final entries = (snapshot.data?.docs ?? [])
            .map((d) => d.data())
            .where((d) => _historyActions.contains(d['action']))
            .take(10)
            .toList();
        if (entries.isEmpty) {
          return const Text(
            'No patches recorded yet.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return BentoCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _historyRow(entries[i], first: i == 0),
            ],
          ),
        );
      },
    );
  }

  Widget _historyRow(Map<String, dynamic> data, {bool first = false}) {
    final action = data['action'];
    final (IconData icon, Color color, Color tint, String title) =
        switch (action) {
          'server_patch_deployed' => (
            Icons.cloud_done_outlined,
            AppColors.primary,
            AppColors.primaryLight,
            'Server patch deployed',
          ),
          'system_patch_applied' => (
            Icons.check_rounded,
            AppColors.success,
            AppColors.successBg,
            'Settings patch applied',
          ),
          _ => (
            Icons.block_rounded,
            AppColors.danger,
            AppColors.dangerBg,
            'Patch rejected',
          ),
        };
    final details = data['details'];
    var detailLine = (data['message'] ?? '').toString();
    if (details is Map && details['changes'] is Map) {
      detailLine = (details['changes'] as Map).entries.map((e) {
        if (e.key == 'minimum_app_version') return 'minimum ${e.value}';
        return (e.value ?? '').toString().isEmpty
            ? 'notice removed'
            : 'notice set';
      }).join(', ');
    }
    final when = [
      adminLogDay(data['timestamp']),
      adminLogTime(data['timestamp']),
    ].where((s) => s.isNotEmpty).join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.surfaceMuted)),
      ),
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
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [detailLine, when].where((s) => s.isNotEmpty).join(' · '),
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

  Widget _resultCard({
    required IconData icon,
    required Color color,
    required Color tint,
    required String title,
    required List<String> lines,
  }) {
    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
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
