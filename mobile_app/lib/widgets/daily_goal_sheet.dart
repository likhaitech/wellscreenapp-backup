import 'package:flutter/material.dart';

import '../models/daily_goal.dart';
import '../theme/app_theme.dart';

/// Three pill buttons: Ages 6 and below / 7–12 / 13–15.
class AgeGroupPicker extends StatelessWidget {
  const AgeGroupPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ChildAgeGroup? selected;
  final ValueChanged<ChildAgeGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final group in ChildAgeGroup.values) ...[
          if (group != ChildAgeGroup.values.first) const SizedBox(width: 8),
          Expanded(child: _option(group)),
        ],
      ],
    );
  }

  Widget _option(ChildAgeGroup group) {
    final on = group == selected;
    return Semantics(
      selected: on,
      button: true,
      label: 'Ages ${group.label}, ${DailyGoal.label(group.defaultMinutes)} '
          'a day',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(group),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: on ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? AppColors.primary : AppColors.border,
              width: on ? 1.5 : 1,
            ),
          ),
          child: ExcludeSemantics(
            child: Column(
              children: [
                Text(
                  group.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DailyGoal.label(group.defaultMinutes)} a day',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet where the guardian sets the child's age group and daily
/// goal. Returns the Firestore fields to save, or null when cancelled.
Future<Map<String, Object>?> showDailyGoalSheet(
  BuildContext context, {
  required String childName,
  required Map<String, dynamic>? profile,
}) {
  return showModalBottomSheet<Map<String, Object>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _DailyGoalSheet(childName: childName, profile: profile),
  );
}

class _DailyGoalSheet extends StatefulWidget {
  const _DailyGoalSheet({required this.childName, required this.profile});

  final String childName;
  final Map<String, dynamic>? profile;

  @override
  State<_DailyGoalSheet> createState() => _DailyGoalSheetState();
}

class _DailyGoalSheetState extends State<_DailyGoalSheet> {
  late ChildAgeGroup? _group =
      ChildAgeGroup.parse(widget.profile?[DailyGoal.ageGroupField]);
  late int _minutes = DailyGoal.minutesFor(widget.profile);

  int get _ageDefault => _group?.defaultMinutes ?? DailyGoal.fallbackMinutes;

  void _step(int delta) =>
      setState(() => _minutes = DailyGoal.clampMinutes(_minutes + delta));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Daily screen-time goal',
              style: TextStyle(
                fontFamily: AppFonts.heading,
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You get an alert when ${widget.childName} reaches it, and '
              'again 2 hours later. It does not lock the phone.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Age group',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            AgeGroupPicker(
              selected: _group,
              onChanged: (group) => setState(() {
                _group = group;
                _minutes = group.defaultMinutes;
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Daily goal',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Less time',
                    onPressed: _minutes > DailyGoal.minMinutes
                        ? () => _step(-DailyGoal.stepMinutes)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DailyGoal.label(_minutes),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppFonts.heading,
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'More time',
                    onPressed: _minutes < DailyGoal.maxMinutes
                        ? () => _step(DailyGoal.stepMinutes)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _group == null
                        ? 'Pick an age group to use its recommended goal.'
                        : 'Recommended for ages ${_group!.label}: '
                              '${DailyGoal.label(_ageDefault)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_group != null && _minutes != _ageDefault)
                  TextButton(
                    onPressed: () => setState(() => _minutes = _ageDefault),
                    child: const Text('Use recommended'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => Navigator.of(context).pop(<String, Object>{
                      if (_group != null) DailyGoal.ageGroupField: _group!.id,
                      DailyGoal.minutesField: _minutes,
                    }),
                    child: const Text('Save goal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
