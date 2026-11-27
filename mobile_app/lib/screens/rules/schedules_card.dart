import 'package:flutter/material.dart';

import '../../models/schedule_rules.dart';
import '../../services/schedule_rules_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wellscreen_ui.dart';

/// Guardian controls for bedtime lock, focus mode and break timers.
/// Every change saves immediately; the child's phone applies it on its
/// next rules sync.
class SchedulesCard extends StatefulWidget {
  const SchedulesCard({super.key});

  @override
  State<SchedulesCard> createState() => _SchedulesCardState();
}

class _SchedulesCardState extends State<SchedulesCard> {
  final ScheduleRulesService _service = ScheduleRulesService();
  ScheduleRules _rules = const ScheduleRules();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await _service.fetch();
      if (!mounted) return;
      setState(() => _rules = rules);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load schedules. Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      final rules = await _service.fetch();
      if (!mounted) return;
      setState(() => _rules = rules);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save. Check your connection and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start
        ? _rules.bedtimeStartMinutes
        : _rules.bedtimeEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: start ? 'Bedtime starts' : 'Bedtime ends',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    final next = start
        ? _rules.copyWith(bedtimeStartMinutes: minutes)
        : _rules.copyWith(bedtimeEndMinutes: minutes);
    final error = next.bedtimeError;
    if (error != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    await _run(() => _service.saveBedtime(next), 'Bedtime saved.');
  }

  int? _focusChoice;

  Widget _hint(String text) => Text(
    text,
    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
  );

  /// Card header row from the mockup: tinted icon box, title, subtitle and
  /// an optional trailing control (a switch).
  Widget _header({
    required IconData icon,
    required Color color,
    required Color tint,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _timeBox(String label, int minutes, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ScheduleRules.timeLabel(minutes),
                style: const TextStyle(
                  fontFamily: AppFonts.heading,
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback? onTap) {
    return Semantics(
      selected: on,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: on ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  /// "60 min" pill that opens a menu of the allowed values.
  Widget _minutesPill({
    required int value,
    required List<int> choices,
    required bool enabled,
    required ValueChanged<int> onChanged,
  }) {
    return PopupMenuButton<int>(
      enabled: enabled,
      tooltip: 'Change',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final m in choices)
          PopupMenuItem(value: m, child: Text('$m min')),
      ],
      child: IgnorePointer(child: _chip('$value min', true, () {})),
    );
  }

  String _focusLabel(int minutes) => minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}';

  @override
  Widget build(BuildContext context) {
    final canEdit = !_loading && !_saving && _error == null;
    final now = DateTime.now();
    final focusOn = _rules.isFocusActive(now);
    final focusEnd = _rules.focusEndsAt;

    if (_loading) {
      return const BentoCard(child: LinearProgressIndicator());
    }
    if (_error != null) {
      return BentoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    const choices = ScheduleRules.focusChoices;
    final focusChoice = _focusChoice != null && choices.contains(_focusChoice)
        ? _focusChoice!
        : (choices.contains(60) ? 60 : choices.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bedtime lock
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                icon: Icons.bedtime_outlined,
                color: AppColors.violet,
                tint: AppColors.violetBg,
                title: 'Bedtime lock',
                subtitle: 'Every app locks during these hours. Calls and '
                    'WellScreen still work.',
                trailing: Switch(
                  value: _rules.bedtimeEnabled,
                  onChanged: canEdit
                      ? (on) => _run(
                          () => _service.saveBedtime(
                            _rules.copyWith(bedtimeEnabled: on),
                          ),
                          on ? 'Bedtime lock on.' : 'Bedtime lock off.',
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _timeBox(
                    'Starts',
                    _rules.bedtimeStartMinutes,
                    canEdit ? () => _pickTime(start: true) : null,
                  ),
                  const SizedBox(width: 10),
                  _timeBox(
                    'Ends',
                    _rules.bedtimeEndMinutes,
                    canEdit ? () => _pickTime(start: false) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Focus mode
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                icon: Icons.center_focus_strong_outlined,
                color: AppColors.primary,
                tint: AppColors.primaryLight,
                title: 'Focus mode',
                subtitle: focusOn && focusEnd != null
                    ? 'On until ${ScheduleRules.timeLabel(focusEnd.hour * 60 + focusEnd.minute)}. '
                          'Apps are paused.'
                    : 'Lock apps now for study time',
              ),
              const SizedBox(height: 12),
              if (focusOn && focusEnd != null)
                FilledButton.icon(
                  onPressed: canEdit
                      ? () => _run(_service.endFocus, 'Focus mode ended.')
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.dangerBg,
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('End focus now'),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in choices)
                      _chip(
                        _focusLabel(minutes),
                        minutes == focusChoice,
                        canEdit
                            ? () => setState(() => _focusChoice = minutes)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: canEdit
                      ? () => _run(
                          () => _service.startFocus(focusChoice),
                          'Focus mode started.',
                        )
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text('Start focus · ${_focusLabel(focusChoice)}'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Break timers (cooldown)
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                icon: Icons.coffee_outlined,
                color: AppColors.success,
                tint: AppColors.successBg,
                title: 'Break timer',
                subtitle: 'A short pause after long non-stop use of one app',
                trailing: Switch(
                  value: _rules.breaksEnabled,
                  onChanged: canEdit
                      ? (on) => _run(
                          () => _service.saveBreaks(
                            _rules.copyWith(breaksEnabled: on),
                          ),
                          on ? 'Break timer on.' : 'Break timer off.',
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'After',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  _minutesPill(
                    value: _rules.breakAfterMinutes,
                    choices: ScheduleRules.breakAfterChoices,
                    enabled: canEdit,
                    onChanged: (m) => _run(
                      () => _service.saveBreaks(
                        _rules.copyWith(breakAfterMinutes: m),
                      ),
                      'Break timer saved.',
                    ),
                  ),
                  const Text(
                    'pause for',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  _minutesPill(
                    value: _rules.breakLengthMinutes,
                    choices: ScheduleRules.breakLengthChoices,
                    enabled: canEdit,
                    onChanged: (m) => _run(
                      () => _service.saveBreaks(
                        _rules.copyWith(breakLengthMinutes: m),
                      ),
                      'Break timer saved.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_saving) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
        _hint(
          'Emergency Access and approved app time still work during '
          'schedules. Changes save right away.',
        ),
      ],
    );
  }
}
