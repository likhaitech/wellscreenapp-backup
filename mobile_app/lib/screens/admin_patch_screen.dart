import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../models/daily_goal.dart';
import '../services/admin_settings_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';

/// Manuscript "Manage System Settings -> Upload System Patch".
///
/// The admin edits the age-group rules in a plain form - no JSON to type.
/// The form only builds the patch; the server validates it (unknown keys,
/// wrong types and out-of-range values are rejected with no change), then
/// applies it to system_settings/global and writes a system log. Guardian
/// and child apps read the rules live from there.
class AdminPatchScreen extends StatefulWidget {
  const AdminPatchScreen({super.key});

  @override
  State<AdminPatchScreen> createState() => _AdminPatchScreenState();
}

class _AgeRow {
  _AgeRow(this.group);

  final ChildAgeGroup group;
  final TextEditingController minutes = TextEditingController();
  int? currentMinutes;
  String? currentRisky;
  String risky = 'review';
}

class _AdminPatchScreenState extends State<AdminPatchScreen> {
  final AdminSettingsApiService _api = AdminSettingsApiService();
  final TextEditingController _note = TextEditingController();
  final List<_AgeRow> _rows = [
    for (final g in ChildAgeGroup.values) _AgeRow(g),
  ];

  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  List<String> _errors = [];
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final row in _rows) {
      row.minutes.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await _api.getSettings();
      for (final row in _rows) {
        final goal = settings['goal_minutes_${row.group.id}'];
        final risky = settings['risky_sites_${row.group.id}'];
        row.currentMinutes = goal is int ? goal : row.group.builtInMinutes;
        row.currentRisky = risky is String
            ? risky
            : (row.group.builtInBlocksRiskySites ? 'block' : 'review');
        row.minutes.text = '${row.currentMinutes}';
        row.risky = row.currentRisky!;
      }
    } catch (e) {
      _loadError = 'Could not load the current settings. The server may be '
          'waking up - try again in a minute.';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Only what the admin changed. Range checks are left to the server, so
  /// a wrong value (for example 5 minutes) shows up as a rejection.
  Map<String, Object> _changes() {
    final changes = <String, Object>{};
    for (final row in _rows) {
      final typed = int.tryParse(row.minutes.text.trim());
      if (typed != null && typed != row.currentMinutes) {
        changes['goal_minutes_${row.group.id}'] = typed;
      }
      if (row.risky != row.currentRisky) {
        changes['risky_sites_${row.group.id}'] = row.risky;
      }
    }
    return changes;
  }

  List<String> _preview() {
    final lines = <String>[];
    for (final row in _rows) {
      final typed = int.tryParse(row.minutes.text.trim());
      if (typed != null && typed != row.currentMinutes) {
        lines.add(
          'Ages ${row.group.label} daily goal: '
          '${row.currentMinutes ?? '-'} min -> $typed min',
        );
      }
      if (row.risky != row.currentRisky) {
        lines.add(
          'Ages ${row.group.label} possible-risk sites: '
          '${_riskyLabel(row.currentRisky)} -> ${_riskyLabel(row.risky)}',
        );
      }
    }
    return lines;
  }

  static String _riskyLabel(String? value) =>
      value == 'block' ? 'Block' : 'Ask guardian';

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
    final note = _note.text.trim();
    setState(() => _busy = true);
    try {
      await _api.applyPatch({
        if (note.isNotEmpty) 'description': note,
        'settings': changes,
      }, validateOnly: validateOnly);
      if (!mounted) return;
      if (validateOnly) {
        setState(
          () => _success =
              'The server checked this change. Nothing is applied yet.',
        );
      } else {
        setState(
          () => _success =
              'Applied and recorded in System logs. Guardian and child '
              'phones pick it up within seconds.',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply this change?'),
        content: Text(
          '${preview.isEmpty ? 'The server will check the values.' : preview.join('\n')}'
          '\n\nIt is recorded in System logs.',
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

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WellScreenAppBar.subPage(title: 'System patch'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Age-group rules for every family. Change a value, '
                    'check it, then apply. The server rejects invalid '
                    'values and nothing changes.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                if (_loadError != null) ...[
                  const SizedBox(height: 12),
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
                  for (final row in _rows) ...[
                    const SizedBox(height: 12),
                    _ageCard(row),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: 'Reason for the change (optional)',
                      filled: true,
                      fillColor: AppColors.surface,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                    ),
                  ),
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
                ],
              ],
            ),
    );
  }

  Widget _ageCard(_AgeRow row) {
    return BentoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ages ${row.group.label}',
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Default daily goal',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: row.minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 3,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    suffixText: 'min',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '15 to 720 minutes. Guardians can still adjust each child.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          const Text(
            'Possible-risk websites',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'block', label: Text('Block')),
              ButtonSegment(value: 'review', label: Text('Ask guardian')),
            ],
            selected: {row.risky},
            onSelectionChanged: (value) =>
                setState(() => row.risky = value.first),
          ),
          const SizedBox(height: 4),
          const Text(
            'Known adult, gambling and drug sites are always blocked.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
