import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../theme/app_theme.dart';
import 'wellscreen_ui.dart';

/// Admin dashboard: active-users graph and background job health.
/// Both show only what the backend recorded - a day the monitoring check
/// did not run is drawn as "no record", never as a made-up number.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String adminDayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Stacked bars per day: guardians (indigo) under child devices (teal).
/// Tap a bar to see that day's numbers.
class AdminActiveUsersChart extends StatefulWidget {
  const AdminActiveUsersChart({
    super.key,
    required this.days,
    required this.range,
    required this.onRangeChanged,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final List<AdminDailyActive> days;

  /// 7 or 30.
  final int range;
  final ValueChanged<int> onRangeChanged;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<AdminActiveUsersChart> createState() => _AdminActiveUsersChartState();
}

class _AdminActiveUsersChartState extends State<AdminActiveUsersChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant AdminActiveUsersChart old) {
    super.didUpdateWidget(old);
    if (old.days.length != widget.days.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final recorded = days.where((d) => d.recorded).toList();
    final selected = _selected != null && _selected! < days.length
        ? days[_selected!]
        : (days.isNotEmpty ? days.last : null);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Active users',
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _rangeChip(7),
              const SizedBox(width: 6),
              _rangeChip(30),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Guardians who opened the app and child devices that checked '
            'in, per day.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (widget.loading && days.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.error != null && days.isEmpty)
            SizedBox(
              height: 150,
              child: Center(
                child: TextButton(
                  onPressed: widget.onRetry,
                  child: Text('${widget.error} Tap to retry.'),
                ),
              ),
            )
          else if (recorded.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'No activity recorded yet. The monitoring check records '
                  'today\'s totals every 5 minutes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            if (selected != null) _selectedLine(selected),
            const SizedBox(height: 10),
            SizedBox(height: 150, child: _bars(days)),
            const SizedBox(height: 6),
            _axis(days),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _legend(AppColors.primary, 'Guardians'),
                _legend(AppColors.teal, 'Child devices'),
                _legend(AppColors.track, 'No record'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rangeChip(int value) {
    final on = widget.range == value;
    return Material(
      color: on ? AppColors.primary : AppColors.surfaceMuted,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: on ? null : () => widget.onRangeChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$value days',
            style: TextStyle(
              color: on ? Colors.white : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedLine(AdminDailyActive d) {
    final today = DateTime.now();
    final isToday = d.date.year == today.year &&
        d.date.month == today.month &&
        d.date.day == today.day;
    final label = isToday ? 'Today' : adminDayLabel(d.date);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: d.recorded ? '${d.total} active' : 'No record',
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFeatures: kTabularFigures,
            ),
          ),
          TextSpan(
            text: d.recorded
                ? '  $label · ${d.activeGuardians} guardian'
                    '${d.activeGuardians == 1 ? '' : 's'}, '
                    '${d.activeChildren} child device'
                    '${d.activeChildren == 1 ? '' : 's'}'
                : '  $label',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
      key: const Key('adminChartSelected'),
    );
  }

  Widget _bars(List<AdminDailyActive> days) {
    var peak = 0;
    for (final d in days) {
      if (d.recorded && d.total > peak) peak = d.total;
    }
    if (peak == 0) peak = 1;
    final gap = days.length > 10 ? 2.0 : 6.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: GestureDetector(
                  key: ValueKey('adminChartBar$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: _bar(
                      days[i],
                      peak: peak,
                      height: height,
                      selected: _selected == null
                          ? i == days.length - 1
                          : _selected == i,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bar(
    AdminDailyActive d, {
    required int peak,
    required double height,
    required bool selected,
  }) {
    const radius = Radius.circular(6);
    if (!d.recorded) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 6,
          decoration: const BoxDecoration(
            color: AppColors.track,
            borderRadius: BorderRadius.all(radius),
          ),
        ),
      );
    }
    final g = height * d.activeGuardians / peak;
    final c = height * d.activeChildren / peak;
    final opacity = selected ? 1.0 : 0.55;
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (d.total == 0)
            Container(
              height: 3,
              decoration: const BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.all(radius),
              ),
            ),
          if (c > 0)
            Container(
              height: c,
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.only(
                  topLeft: radius,
                  topRight: radius,
                  bottomLeft: g > 0 ? Radius.zero : radius,
                  bottomRight: g > 0 ? Radius.zero : radius,
                ),
              ),
            ),
          if (g > 0)
            Container(
              height: g,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: c > 0 ? Radius.zero : radius,
                  topRight: c > 0 ? Radius.zero : radius,
                  bottomLeft: radius,
                  bottomRight: radius,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _axis(List<AdminDailyActive> days) {
    final every = days.length > 10 ? 5 : 1;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Text(
              (days.length - 1 - i) % every == 0
                  ? (days.length > 10
                      ? '${days[i].date.day}'
                      : _weekdays[days[i].date.weekday - 1])
                  : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// "Background jobs" card: last run of each scheduled backend job.
class AdminJobHealthCard extends StatelessWidget {
  const AdminJobHealthCard({
    super.key,
    required this.jobs,
    this.loaded = true,
    this.now,
  });

  final Map<String, AdminJobStatus?> jobs;
  final bool loaded;
  final DateTime? now;

  static const _names = {
    'monitoring': ('Monitoring check', 'Every 5 minutes', 15),
    'chat_notifications': ('Chat notifications', 'Every 5 minutes', 15),
    'data_cleanup': ('90-day data cleanup', 'Daily', 60 * 26),
  };

  /// (label, color, tint) for one job. A job that ran OK but not within
  /// its expected window is shown as late.
  static (String, Color, Color) status(
    AdminJobStatus? job, {
    required int lateAfterMinutes,
    required DateTime now,
  }) {
    if (job == null) {
      return ('Not set up', AppColors.textSecondary, AppColors.surfaceMuted);
    }
    if (!job.ok) return ('Failed', AppColors.danger, AppColors.dangerBg);
    final last = job.lastRunAt;
    if (last == null || now.difference(last).inMinutes > lateAfterMinutes) {
      return ('Late', AppColors.warning, AppColors.warningBg);
    }
    return ('OK', AppColors.success, AppColors.successBg);
  }

  static String lastRunLabel(DateTime? last, DateTime now) {
    if (last == null) return 'Never ran';
    final minutes = now.difference(last).inMinutes;
    if (minutes < 1) return 'Last run just now';
    if (minutes < 60) return 'Last run $minutes min ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'Last run $hours h ago';
    return 'Last run ${adminDayLabel(last)}';
  }

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Background jobs',
            style: TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final entry in _names.entries)
            _row(entry.key, entry.value, at),
        ],
      ),
    );
  }

  Widget _row(String key, (String, String, int) info, DateTime at) {
    final (title, schedule, late) = info;
    final job = jobs[key];
    final (label, color, tint) = loaded
        ? status(job, lateAfterMinutes: late, now: at)
        : ('-', AppColors.textSecondary, AppColors.surfaceMuted);
    final sub = !loaded
        ? schedule
        : (job == null
            ? '$schedule · no run recorded'
            : '$schedule · ${lastRunLabel(job.lastRunAt, at)}');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
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
                  sub,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
