import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../services/app_release_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';

/// Manuscript "Manage System Settings -> Upload System Patch".
///
/// A patch itself is a code change: pushed, then the backend redeploys and
/// records the new server version in System logs. This page is how the
/// admin rolls the fix out and checks it landed:
/// - the server version that is running now;
/// - the minimum app version - phones below it must update first;
/// - a maintenance notice shown to every user;
/// - the patch history (deploys and applied/rejected patches).
/// The server validates every change (version must be like 1.4.0, notice
/// at most 200 characters); a rejected change does nothing and is logged.
class AdminPatchScreen extends StatefulWidget {
  const AdminPatchScreen({super.key});

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
  final TextEditingController _minimum = TextEditingController();
  final TextEditingController _notice = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  String _serverVersion = '-';
  String? _runningSince;
  String _currentMinimum = '1.0.0';
  String _currentNotice = '';
  String? _thisAppVersion;
  List<String> _errors = [];
  String? _success;

  @override
  void initState() {
    super.initState();
    AppReleaseService.installedVersion().then((v) {
      if (mounted) setState(() => _thisAppVersion = v);
    }).catchError((Object _) {});
    _load();
  }

  @override
  void dispose() {
    _minimum.dispose();
    _notice.dispose();
    super.dispose();
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
      _minimum.text = _currentMinimum;
      _notice.text = _currentNotice;
    } catch (e) {
      _loadError = 'Could not load the current settings. The server may be '
          'waking up - try again in a minute.';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Only what changed. Format checks are left to the server, so a wrong
  /// version (for example "1.4") is shown as a rejection.
  Map<String, Object> _changes() {
    final minimum = _minimum.text.trim();
    final notice = _notice.text.trim();
    return {
      if (minimum.isNotEmpty && minimum != _currentMinimum)
        'minimum_app_version': minimum,
      if (notice != _currentNotice) 'maintenance_message': notice,
    };
  }

  List<String> _preview() {
    final changes = _changes();
    final notice = changes['maintenance_message'];
    return [
      if (changes.containsKey('minimum_app_version'))
        'Minimum app version: $_currentMinimum -> '
            '${changes['minimum_app_version']}',
      if (notice is String)
        notice.isEmpty
            ? 'Maintenance notice: removed'
            : 'Maintenance notice: "$notice"',
    ];
  }

  Future<void> _run({required bool validateOnly}) async {
    setState(() {
      _errors = [];
      _success = null;
    });
    final changes = _changes();
    if (changes.isEmpty) {
      setState(() => _errors = ['Nothing changed yet.']);
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.applyPatch({'settings': changes}, validateOnly: validateOnly);
      if (!mounted) return;
      if (validateOnly) {
        setState(
          () => _success =
              'The server checked this change. Nothing is applied yet.',
        );
      } else {
        setState(
          () => _success =
              'Applied and recorded in System logs. Phones pick it up '
              'within seconds.',
        );
        await _load();
      }
    } on SystemPatchRejected catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors = ['Request failed: $e']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmApply() async {
    final preview = _preview();
    final minimum = _changes()['minimum_app_version'];
    final thisApp = _thisAppVersion;
    final warnsOldPhones = minimum is String &&
        AppReleaseService.isVersion(minimum) &&
        thisApp != null &&
        AppReleaseService.needsUpdate(thisApp, minimum);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply this patch?'),
        content: Text(
          [
            if (preview.isNotEmpty) preview.join('\n'),
            if (warnsOldPhones)
              'Phones on version $thisApp (this build) will have to '
                  'update before they can continue.',
            'It is recorded in System logs.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(validateOnly: false);
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
    final preview = _preview();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
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
                  _minimumCard(),
                  const SizedBox(height: 12),
                  _noticeCard(),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _resultCard(
                      icon: Icons.compare_arrows_rounded,
                      color: AppColors.primary,
                      tint: AppColors.primaryLight,
                      title: 'Changes',
                      lines: preview,
                    ),
                  ],
                  if (_errors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _resultCard(
                      icon: Icons.error_outline_rounded,
                      color: AppColors.danger,
                      tint: AppColors.dangerBg,
                      title: 'Rejected - no changes made',
                      lines: _errors,
                    ),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 12),
                    _resultCard(
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                      tint: AppColors.successBg,
                      title: _success!,
                      lines: const [],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: AppColors.primary,
                            minimumSize: const Size.fromHeight(50),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _run(validateOnly: true),
                          child: const Text('Check'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _busy ? null : _confirmApply,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const AdminSectionTitle('Patch history'),
                  const SizedBox(height: 8),
                  _history(),
                ],
              ],
            ),
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

  Widget _cardTitle(String title, String help) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppFonts.heading,
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          help,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      counterText: '',
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _minimumCard() {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            'Minimum app version',
            'After a bug-fix release, raise this so phones on an older '
                'version must update first. Format: 1.4.0',
          ),
          TextField(
            controller: _minimum,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            maxLength: 11,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard() {
    final length = _notice.text.trim().length;
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            'Maintenance notice',
            'Shown at the top of every guardian and child screen. Leave '
                'empty for no notice.',
          ),
          TextField(
            controller: _notice,
            maxLines: 3,
            minLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              'e.g. Server maintenance tonight at 10 PM',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$length/200',
            style: TextStyle(
              color: length > 200 ? AppColors.danger : AppColors.textSecondary,
              fontSize: 11,
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
