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
    if (next.bedtimeStartMinutes == next.bedtimeEndMinutes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and end time must be different.')),
      );
      return;
    }
    await _run(() => _service.saveBedtime(next), 'Bedtime saved.');
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 2),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _hint(String text) => Text(
    text,
    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
  );

  @override
  Widget build(BuildContext context) {
    final canEdit = !_loading && !_saving && _error == null;
    final now = DateTime.now();
    final focusOn = _rules.isFocusActive(now);
    final focusEnd = _rules.focusEndsAt;

    return BentoCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: const Icon(Icons.schedule_rounded, color: AppColors.primary),
        title: const Text(
          'Schedules',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'Bedtime lock, focus mode and breaks.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ] else ...[
            // Bedtime lock
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bedtime lock'),
              subtitle: Text(
                'Pauses apps from '
                '${ScheduleRules.timeLabel(_rules.bedtimeStartMinutes)} to '
                '${ScheduleRules.timeLabel(_rules.bedtimeEndMinutes)}. '
                'Calls and WellScreen still work.',
              ),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canEdit ? () => _pickTime(start: true) : null,
                    child: Text(
                      'From ${ScheduleRules.timeLabel(_rules.bedtimeStartMinutes)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canEdit ? () => _pickTime(start: false) : null,
                    child: Text(
                      'To ${ScheduleRules.timeLabel(_rules.bedtimeEndMinutes)}',
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Focus mode
            _sectionTitle('Focus mode'),
            if (focusOn && focusEnd != null) ...[
              _hint(
                'On until ${ScheduleRules.timeLabel(focusEnd.hour * 60 + focusEnd.minute)}. '
                'Apps are paused; calls and WellScreen still work.',
              ),
              TextButton.icon(
                onPressed: canEdit
                    ? () => _run(_service.endFocus, 'Focus mode ended.')
                    : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End focus now'),
              ),
            ] else ...[
              _hint('Pause apps right now for study or family time.'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final minutes in ScheduleRules.focusChoices)
                    ActionChip(
                      label: Text(
                        minutes < 60
                            ? '$minutes min'
                            : '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}',
                      ),
                      onPressed: canEdit
                          ? () => _run(
                              () => _service.startFocus(minutes),
                              'Focus mode started.',
                            )
                          : null,
                    ),
                ],
              ),
            ],
            const Divider(height: 24),

            // Break timers (cooldown)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Break timer'),
              subtitle: Text(
                'After ${_rules.breakAfterMinutes} min of non-stop use of one '
                'app, that app pauses for ${_rules.breakLengthMinutes} min.',
              ),
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
            Row(
              children: [
                const Text('After '),
                DropdownButton<int>(
                  value: _rules.breakAfterMinutes,
                  items: [
                    for (final m in ScheduleRules.breakAfterChoices)
                      DropdownMenuItem(value: m, child: Text('$m min')),
                  ],
                  onChanged: canEdit
                      ? (m) => m == null
                            ? null
                            : _run(
                                () => _service.saveBreaks(
                                  _rules.copyWith(breakAfterMinutes: m),
                                ),
                                'Break timer saved.',
                              )
                      : null,
                ),
                const Text('  pause '),
                DropdownButton<int>(
                  value: _rules.breakLengthMinutes,
                  items: [
                    for (final m in ScheduleRules.breakLengthChoices)
                      DropdownMenuItem(value: m, child: Text('$m min')),
                  ],
                  onChanged: canEdit
                      ? (m) => m == null
                            ? null
                            : _run(
                                () => _service.saveBreaks(
                                  _rules.copyWith(breakLengthMinutes: m),
                                ),
                                'Break timer saved.',
                              )
                      : null,
                ),
              ],
            ),
            if (_saving) const LinearProgressIndicator(),
            const SizedBox(height: 6),
            _hint(
              'Emergency Access and approved app time still work during '
              'schedules.',
            ),
          ],
        ],
      ),
    );
  }
}
