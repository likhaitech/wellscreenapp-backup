import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/weekly_summary.dart';
import '../theme/app_theme.dart';

/// The guardian's "This week" sheet: a daily bar chart with the goal line,
/// headline numbers, and a donut of the most used apps.
class WeeklySummarySheet extends StatelessWidget {
  const WeeklySummarySheet({
    super.key,
    required this.week,
    required this.goal,
    required this.childName,
    required this.now,
  });

  final WeeklySummary week;
  final Duration goal;
  final String childName;
  final DateTime now;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Colours of the top apps in the donut and its legend.
  static const appColors = [
    Color(0xFF3438B8),
    Color(0xFF7024B8),
    Color(0xFF52B8A0),
    Color(0xFFE6A23C),
    Color(0xFFDB4E5E),
  ];
  static const _otherColor = Color(0xFFD5D8E8);

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return m == 0 ? '${h}h' : '${h}h ${m}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  static String _shortDuration(Duration d) {
    if (d.inMinutes >= 60) {
      final hours = d.inMinutes / 60;
      return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)}h';
    }
    return '${d.inMinutes}m';
  }

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  String _day(DateTime d) => _weekdays[d.weekday - 1];

  bool _isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;

  @override
  Widget build(BuildContext context) {
    final first = week.days.first.key;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text(
              'This week',
              style: TextStyle(
                fontFamily: AppFonts.heading,
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$childName · ${_date(first)} – ${_date(now)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            if (week.daysWithData == 0)
              _emptyState()
            else ...[
              _heroCard(),
              const SizedBox(height: 16),
              _sectionTitle('Daily screen time'),
              const SizedBox(height: 10),
              _barChart(),
              const SizedBox(height: 16),
              _statRow(),
              const SizedBox(height: 20),
              _sectionTitle('Most used apps this week'),
              const SizedBox(height: 12),
              _appsSection(),
              const SizedBox(height: 14),
              const Text(
                'Days with no reading are not counted. WellScreen itself is '
                'not counted as screen time.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Column(
      children: [
        Icon(Icons.bar_chart_rounded, size: 40, color: AppColors.textDisabled),
        SizedBox(height: 8),
        Text(
          'No screen time synced this week yet. Ask your child to open '
          'WellScreen and tap Sync usage now.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    ),
  );

  /// Gradient card: total and daily average, and the change from usual.
  Widget _heroCard() {
    final percent = week.percentVsUsual;
    String chip;
    IconData chipIcon;
    if (percent == null) {
      chip = 'Not enough days to compare yet';
      chipIcon = Icons.hourglass_empty_rounded;
    } else if (percent == 0) {
      chip = 'Same as the 30-day average';
      chipIcon = Icons.drag_handle_rounded;
    } else if (percent > 0) {
      chip = '$percent% above the 30-day average';
      chipIcon = Icons.trending_up_rounded;
    } else {
      chip = '${-percent}% below the 30-day average';
      chipIcon = Icons.trending_down_rounded;
    }

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppFonts.heading,
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat('Total this week', duration(week.total)),
              stat('Daily average', duration(week.dailyAverage!)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chipIcon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    chip,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  /// Seven bars with the daily goal as a dashed line. Days over the goal
  /// are red; today is outlined.
  Widget _barChart() {
    const chartHeight = 150.0;
    var maxMs = goal.inMilliseconds;
    for (final day in week.days) {
      final ms = day.value?.inMilliseconds ?? 0;
      if (ms > maxMs) maxMs = ms;
    }
    if (maxMs <= 0) maxMs = 1;
    final goalY = goal > Duration.zero
        ? chartHeight * goal.inMilliseconds / maxMs
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: chartHeight + 18,
            child: Stack(
              children: [
                if (goalY != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: goalY,
                    child: Row(
                      children: [
                        Expanded(
                          child: CustomPaint(
                            size: const Size(double.infinity, 1),
                            painter: _DashPainter(AppColors.warning),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Goal ${duration(goal)}',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in week.days)
                      Expanded(child: _bar(day, maxMs, chartHeight)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final day in week.days)
                Expanded(
                  child: Text(
                    _isToday(day.key) ? 'Today' : _day(day.key),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isToday(day.key)
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight:
                          _isToday(day.key) ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.primary, 'Within goal'),
              const SizedBox(width: 14),
              _legendDot(AppColors.danger, 'Over goal'),
              const SizedBox(width: 14),
              _legendDot(const Color(0xFFE3E5F2), 'No data'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(MapEntry<DateTime, Duration?> day, int maxMs, double height) {
    final value = day.value;
    final over = value != null && goal > Duration.zero && value > goal;
    final barHeight = value == null
        ? 6.0
        : math.max(6.0, height * value.inMilliseconds / maxMs);
    final color = value == null
        ? const Color(0xFFE3E5F2)
        : (over ? AppColors.danger : AppColors.primary);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          value == null ? '' : _shortDuration(value),
          style: TextStyle(
            color: over ? AppColors.danger : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: _isToday(day.key)
                ? Border.all(color: AppColors.textPrimary, width: 1.5)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
    ],
  );

  /// Three tiles: a ring for days over the goal, the busiest and the
  /// lightest day.
  Widget _statRow() {
    final over = week.daysOverGoal;
    final counted = week.daysWithData;
    final busiest = week.busiest;
    final lightest = week.lightest;

    Widget tile({required Widget top, required String label, required String sub}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 44, child: top),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );

    Widget iconBadge(IconData icon, Color color, Color bg) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 24),
      ),
    );

    return Row(
      children: [
        tile(
          top: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: counted == 0 ? 0 : over / counted,
                    strokeWidth: 5,
                    color: over > 0 ? AppColors.danger : AppColors.success,
                    backgroundColor: const Color(0xFFE3E5F2),
                  ),
                  Text(
                    '$over/$counted',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          label: 'Over goal',
          sub: '$over of $counted days',
        ),
        const SizedBox(width: 8),
        tile(
          top: iconBadge(
            Icons.local_fire_department_rounded,
            AppColors.danger,
            AppColors.dangerBg,
          ),
          label: busiest == null ? '—' : duration(busiest.value),
          sub: busiest == null
              ? 'Busiest day'
              : 'Busiest · ${_day(busiest.key)}',
        ),
        const SizedBox(width: 8),
        tile(
          top: iconBadge(
            Icons.spa_rounded,
            AppColors.success,
            const Color(0xFFE1F3EE),
          ),
          label: lightest == null ? '—' : duration(lightest.value),
          sub: lightest == null
              ? 'Lightest day'
              : 'Lightest · ${_day(lightest.key)}',
        ),
      ],
    );
  }

  /// Donut of the top apps' share of the week, with a legend.
  Widget _appsSection() {
    final apps = week.topApps;
    if (apps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Appears after the child\'s phone syncs (open WellScreen and tap '
          'Sync usage now).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    final listedShare = apps.fold<double>(0, (sum, a) => sum + a.share);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _DonutPainter(
                    shares: [for (final a in apps) a.share],
                    colors: appColors,
                    otherColor: _otherColor,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(listedShare * 100).round()}%',
                      style: const TextStyle(
                        fontFamily: AppFonts.heading,
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'top ${apps.length} apps',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < apps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: appColors[i % appColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            apps[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          duration(apps[i].duration),
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
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 5, size.width), 0), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.shares,
    required this.colors,
    required this.otherColor,
  });

  final List<double> shares;
  final List<Color> colors;
  final Color otherColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    // The rest of the week (other apps) as a light ring underneath.
    paint.color = otherColor;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    var start = -math.pi / 2;
    for (var i = 0; i < shares.length; i++) {
      final sweep = math.pi * 2 * shares[i].clamp(0.0, 1.0);
      if (sweep <= 0) continue;
      paint.color = colors[i % colors.length];
      // A small gap between slices.
      canvas.drawArc(rect, start, math.max(0.0, sweep - 0.03), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.shares != shares;
}
