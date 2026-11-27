import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/daily_goal.dart';
import '../utils/child_name.dart';
import 'daily_usage_history.dart';
import 'weekly_summary.dart';

/// Builds a PDF export of a child profile's latest report data (usage,
/// browsing, location, alerts) and hands it to the platform share sheet so
/// a guardian can save it or send it elsewhere.
///
/// This reads the same `child_profiles/{childProfileId}` document that
/// reports_screen.dart's four tabs render from - it does a one-off `.get()`
/// rather than subscribing to the live stream, since an export is a single
/// point-in-time snapshot, not something that should regenerate on every
/// Firestore update while the user is looking at a share sheet.
class ReportExportService {
  const ReportExportService._();

  static Future<String> exportChildReport(String childProfileId) async {
    if (childProfileId.isEmpty) {
      throw ArgumentError('childProfileId must not be empty.');
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .get();

    if (!snapshot.exists) {
      throw StateError('Child profile not found.');
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final childName = childNameOf(data, fallback: 'Child Profile');
    final generatedAt = DateTime.now();
    Uint8List? logo;
    try {
      logo = (await rootBundle.load(logoAsset)).buffer.asUint8List();
    } catch (_) {
      logo = null; // The report still works without the logo.
    }
    final pdf = buildReport(data, generatedAt, logo: logo);

    final directory = await getTemporaryDirectory();
    final safeChildName = childName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final timestamp = generatedAt.millisecondsSinceEpoch;
    final file = File(
      '${directory.path}/wellscreen_report_${safeChildName}_$timestamp.pdf',
    );
    await file.writeAsBytes(await pdf.save());

    // Share.shareXFiles() is deprecated as of share_plus 11 (removed the
    // old static-method surface in favor of a singleton) - SharePlus
    // .instance.share() is the replacement `flutter analyze` expects.
    // Confirmed via CI (Build APK run #35): the old call still compiled
    // and ran fine, but `flutter analyze` treats the resulting `info`-
    // level deprecated_member_use lints as failures (exit code 1),
    // same as any other analyzer issue.
    final shareResult = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text: 'WellScreen report for $childName',
        subject: 'WellScreen Report - $childName',
      ),
    );

    if (shareResult.status == ShareResultStatus.dismissed) {
      // Not an error - the guardian just closed the share sheet without
      // picking a destination. The PDF still exists at file.path if the
      // caller wants to surface a "saved to device" fallback message.
    }

    return file.path;
  }

  /// The PDF for one child's report data (usage, browsing, location and
  /// alerts), without saving or sharing it.
  static const String logoAsset = 'assets/icons/wellscreen_icon.png';

  static pw.Document buildReport(
    Map<String, dynamic> data,
    DateTime generatedAt, {
    Uint8List? logo,
  }) {
    final childName = childNameOf(data, fallback: 'Child Profile');
    final logoImage = logo == null ? null : pw.MemoryImage(logo);
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(childName, generatedAt, logoImage),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _buildUsageSection(data),
          pw.SizedBox(height: 18),
          _buildWeeklySection(data, generatedAt),
          pw.SizedBox(height: 18),
          _buildBrowsingSection(data),
          pw.SizedBox(height: 18),
          _buildLocationSection(data),
          pw.SizedBox(height: 18),
          _buildAlertsSection(data),
        ],
      ),
    );
    return pdf;
  }

  // -------------------------------------------------------------------
  // Section builders - mirror reports_screen.dart's four tabs (Usage,
  // Browsing, Location, Alerts) so the exported PDF matches what the
  // guardian already sees in-app, just in a form they can save or send.
  // -------------------------------------------------------------------

  static pw.Widget _buildHeader(
    String childName,
    DateTime generatedAt,
    pw.ImageProvider? logo,
  ) {
    final formatted =
        '${generatedAt.month.toString().padLeft(2, '0')}/'
        '${generatedAt.day.toString().padLeft(2, '0')}/'
        '${generatedAt.year} '
        '${generatedAt.hour.toString().padLeft(2, '0')}:'
        '${generatedAt.minute.toString().padLeft(2, '0')}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 40, height: 40),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'WellScreen Report',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _primary,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$childName  ·  Generated $formatted',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _kv(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );

  static pw.Widget _emptyNote(String message) => pw.Text(
    message,
    style: pw.TextStyle(
      fontSize: 10,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.grey600,
    ),
  );

  /// Public (not `_formatDuration`) so report_export_service_test.dart can
  /// exercise this pure formatting logic directly - previously private and
  /// therefore untestable from outside this file, same reasoning as every
  /// other pure-logic extraction in this codebase (see
  /// usage_tracking_service.dart's countMaxAppOpens() for the established
  /// pattern). No behavior change - purely a visibility rename.
  static String formatDuration(dynamic totalMs) {
    if (totalMs is! num) return 'Not available';
    final duration = Duration(milliseconds: totalMs.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours h $minutes m';
    if (minutes > 0) return '$minutes m';
    return '${duration.inSeconds} s';
  }

  /// Public for the same testability reason as [formatDuration] above.
  static String formatTimestamp(dynamic value) {
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

  /// Public for the same testability reason as [formatDuration] above.
  static List<Map<String, dynamic>> decodeLog(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  // Weekly Summary: the same numbers as the guardian's "This week" sheet
  // (WeeklySummary), with a bar chart of the last 7 days and the top apps.
  static const _primary = PdfColor.fromInt(0xFF3438B8);
  static const _danger = PdfColor.fromInt(0xFFC62F4B);
  static const _goalLine = PdfColor.fromInt(0xFF9A5B00);
  static const _noData = PdfColor.fromInt(0xFFE3E5F2);
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Daily totals plus today's latest report when it is newer (as on the
  /// guardian dashboard).
  static Map<String, int> weeklyTotals(Map<String, dynamic> data, DateTime now) {
    final totals = DailyUsageHistory.parse(data['dailyUsageTotals']);
    final report = data['latestUsageReport'];
    final updatedAt = data['usageReportUpdatedAt'];
    if (report is Map && updatedAt is Timestamp) {
      final at = updatedAt.toDate();
      final live = report['totalUsageDurationMs'];
      final todayKey = DailyUsageHistory.dayKey(now);
      if (at.year == now.year && at.month == now.month && at.day == now.day &&
          live is num && live > (totals[todayKey] ?? 0)) {
        totals[todayKey] = live.toInt();
      }
    }
    return totals;
  }

  static pw.Widget _buildWeeklySection(Map<String, dynamic> data, DateTime now) {
    final goal = DailyGoal.durationFor(data);
    final report = data['latestUsageReport'];
    final week = WeeklySummary.from(
      totals: weeklyTotals(data, now),
      goal: goal,
      now: now,
      weeklyTopApps: report is Map ? report['weeklyTopApps'] : null,
      weeklyAppsTotalMs: report is Map ? report['weeklyAppsTotalMs'] : null,
    );
    if (week.daysWithData == 0) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Weekly Summary'),
          _emptyNote('No screen time synced in the last 7 days.'),
        ],
      );
    }

    String day(DateTime d) => _weekdays[d.weekday - 1];
    final percent = week.percentVsUsual;
    final vsUsual = percent == null
        ? 'Not enough days yet'
        : percent == 0
        ? 'Same as the 30-day average'
        : '${percent.abs()}% ${percent > 0 ? 'above' : 'below'} the 30-day '
              'average (${formatDuration(week.usualAverage!.inMilliseconds)} a day)';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Weekly Summary (last 7 days)'),
        _kv('Total this week', formatDuration(week.total.inMilliseconds)),
        _kv('Daily average', formatDuration(week.dailyAverage!.inMilliseconds)),
        _kv(
          'Days over the goal',
          '${week.daysOverGoal} of ${week.daysWithData} days '
              '(goal ${formatDuration(goal.inMilliseconds)})',
        ),
        if (week.busiest != null)
          _kv(
            'Busiest day',
            '${day(week.busiest!.key)} - '
                '${formatDuration(week.busiest!.value.inMilliseconds)}',
          ),
        if (week.lightest != null)
          _kv(
            'Lightest day',
            '${day(week.lightest!.key)} - '
                '${formatDuration(week.lightest!.value.inMilliseconds)}',
          ),
        _kv('Compared with usual', vsUsual),
        pw.SizedBox(height: 10),
        _weeklyBarChart(week, goal, now),
        pw.SizedBox(height: 12),
        pw.Text(
          'Most used apps this week',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (week.topApps.isEmpty)
          _emptyNote('Appears after the child\'s phone syncs.')
        else
          for (final app in week.topApps) _appShareRow(app),
      ],
    );
  }

  /// Seven bars; red when over the goal, with the goal as a line.
  static pw.Widget _weeklyBarChart(WeeklySummary week, Duration goal, DateTime now) {
    const height = 90.0;
    var maxMs = goal.inMilliseconds;
    for (final d in week.days) {
      final ms = d.value?.inMilliseconds ?? 0;
      if (ms > maxMs) maxMs = ms;
    }
    if (maxMs <= 0) maxMs = 1;
    final goalY = goal > Duration.zero ? height * goal.inMilliseconds / maxMs : null;

    String label(Duration d) => d.inMinutes >= 60
        ? '${(d.inMinutes / 60).toStringAsFixed(1)}h'
        : '${d.inMinutes}m';
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.SizedBox(
            height: height + 14,
            child: pw.Stack(
              children: [
                if (goalY != null)
                  pw.Positioned(
                    left: 0,
                    right: 0,
                    bottom: goalY,
                    child: pw.Container(height: 0.8, color: _goalLine),
                  ),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    for (final d in week.days)
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text(
                              d.value == null ? '' : label(d.value!),
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                            pw.SizedBox(height: 1),
                            pw.Container(
                              width: 18,
                              height: d.value == null
                                  ? 3
                                  : (height * d.value!.inMilliseconds / maxMs)
                                        .clamp(3.0, height),
                              color: d.value == null
                                  ? _noData
                                  : (goal > Duration.zero && d.value! > goal
                                        ? _danger
                                        : _primary),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            children: [
              for (final d in week.days)
                pw.Expanded(
                  child: pw.Text(
                    isToday(d.key) ? 'Today' : _weekdays[d.key.weekday - 1],
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Blue: within goal   Red: over goal   Line: daily goal '
            '(${formatDuration(goal.inMilliseconds)})',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  /// Today's top five apps as bars, longest first.
  static List<pw.Widget> _todayAppBars(List<Map<String, dynamic>> apps) {
    final top = apps
        .where((a) => a['usageDurationMs'] is num)
        .take(5)
        .toList();
    if (top.isEmpty) return const [];
    final longest = (top.first['usageDurationMs'] as num).toDouble();
    return [
      for (final app in top)
        _appShareRow(
          WeeklyApp(
            packageName: (app['packageName'] ?? '').toString(),
            name: (app['displayName'] ?? app['packageName'] ?? '').toString(),
            duration: Duration(
              milliseconds: (app['usageDurationMs'] as num).toInt(),
            ),
            share: longest <= 0
                ? 0
                : (app['usageDurationMs'] as num).toDouble() / longest,
          ),
          showPercent: false,
        ),
    ];
  }

  static pw.Widget _appShareRow(WeeklyApp app, {bool showPercent = true}) =>
      pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(app.name, style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.Container(
          width: 160,
          height: 8,
          color: _noData,
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: 160 * app.share.clamp(0.0, 1.0),
            height: 8,
            color: _primary,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          showPercent
              ? '${formatDuration(app.duration.inMilliseconds)} '
                    '(${(app.share * 100).round()}%)'
              : formatDuration(app.duration.inMilliseconds),
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );

  static pw.Widget _buildUsageSection(Map<String, dynamic> data) {
    final report = data['latestUsageReport'];

    if (report is! Map) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Usage Summary'),
          _emptyNote('No usage data synced yet.'),
        ],
      );
    }

    final reportMap = Map<String, dynamic>.from(report);
    final rawApps = reportMap['topApps'];
    final apps = rawApps is List
        ? rawApps
              .whereType<Map>()
              .map((app) => Map<String, dynamic>.from(app))
              .toList()
        : <Map<String, dynamic>>[];
    final topAppNames = apps
        .take(5)
        .map(
          (app) => (app['displayName'] ?? app['packageName'] ?? '')
              .toString(),
        )
        .where((name) => name.isNotEmpty)
        .join(', ');
    final unhealthyCount = reportMap['unhealthyAppCount'];
    final mlRiskAssessment = data['mlRiskAssessment'];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Usage Summary'),
        _kv(
          'Screen time today',
          formatDuration(reportMap['totalUsageDurationMs']),
        ),
        _kv('Last synced', formatTimestamp(data['usageReportUpdatedAt'])),
        _kv('Top apps', topAppNames.isEmpty ? 'None recorded' : topAppNames),
        _kv(
          'Apps flagged unhealthy',
          '${unhealthyCount is num ? unhealthyCount.toInt() : 0}',
        ),
        _kv(
          'Detected pattern',
          (reportMap['patternStatus'] ?? 'healthy').toString(),
        ),
        _kv(
          'Recommendation',
          (reportMap['recommendationMessage'] ?? 'None').toString(),
        ),
        if (mlRiskAssessment is Map)
          _kv(
            'AI risk assessment',
            '${(mlRiskAssessment['label'] ?? 'Unknown')}'
                '${mlRiskAssessment['confidence'] is num ? ' (${((mlRiskAssessment['confidence'] as num) * 100).toStringAsFixed(0)}%)' : ''}',
          ),
        if (apps.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Most used apps today',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          ..._todayAppBars(apps),
        ],
      ],
    );
  }

  static pw.Widget _buildBrowsingSection(Map<String, dynamic> data) {
    final log = decodeLog(data['browsingLog']);

    if (log.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Browsing Activity'),
          _emptyNote('No flagged browsing activity recorded.'),
        ],
      );
    }

    // Most recent first, capped so the export stays a reasonable length -
    // matches the in-app _ExpandableList's "preview then Show all" intent,
    // just without an interactive toggle in a static PDF.
    final entries = log.reversed.take(30).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Browsing Activity (${log.length} total, most recent ${entries.length} shown)'),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.5),
            2: pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _tableCell('Domain', bold: true),
                _tableCell('Category', bold: true),
                _tableCell('Time', bold: true),
              ],
            ),
            for (final entry in entries)
              pw.TableRow(
                children: [
                  _tableCell((entry['domain'] ?? entry['url'] ?? 'Unknown').toString()),
                  _tableCell((entry['category'] ?? 'flagged').toString()),
                  _tableCell(formatTimestamp(entry['timestamp'])),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableCell(String text, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static pw.Widget _buildLocationSection(Map<String, dynamic> data) {
    final location = data['latestLocation'];

    if (location is! Map) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Location'),
          _emptyNote('No GPS location shared yet.'),
        ],
      );
    }

    final locationMap = Map<String, dynamic>.from(location);
    final label = locationMap['label'];
    final latitude = locationMap['latitude'];
    final longitude = locationMap['longitude'];
    final subtitle = label != null && label.toString().isNotEmpty
        ? label.toString()
        : (latitude is num && longitude is num)
        ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
        : 'Not available';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Location'),
        _kv('Last known location', subtitle),
        _kv('Last synced', formatTimestamp(data['locationUpdatedAt'])),
      ],
    );
  }

  static pw.Widget _buildAlertsSection(Map<String, dynamic> data) {
    final smsLog = decodeLog(data['smsAlertLog']);
    final restrictionLog = decodeLog(data['restrictionLog']);
    final pushAlertLog = decodeLog(data['pushAlertLog']);

    // restrictionLog mixes two legitimate enforcement outcomes - "blocked"
    // (the restriction held) and "emergency_access_bypass" (the parent
    // approved a temporary bypass, logged honestly rather than hidden) -
    // plus any failure outcomes. Counting the whole log as "blocks" would
    // overstate how many apps were actually blocked whenever a bypass was
    // granted. Same distinction reports_screen.dart's in-app summary makes
    // (see its restrictionFailed calculation) - split out here too so the
    // exported PDF and the in-app numbers agree.
    final restrictionBlocked = restrictionLog
        .where((e) => e['outcome'] == 'blocked')
        .length;
    final emergencyBypasses = restrictionLog
        .where((e) => e['outcome'] == 'emergency_access_bypass')
        .length;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Alerts'),
        _kv('SMS backup alerts sent', '${smsLog.length}'),
        _kv('Restricted-app blocks', '$restrictionBlocked'),
        _kv('Emergency access grants', '$emergencyBypasses'),
        _kv('Push notifications delivered', '${pushAlertLog.length}'),
        if (restrictionLog.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Most recent restriction events:',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          for (final entry in restrictionLog.reversed.take(10))
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2, left: 8),
              child: pw.Text(
                '- ${entry['packageName'] ?? 'unknown app'} · '
                '${entry['outcome'] ?? 'unknown'} · '
                '${formatTimestamp(entry['timestamp'])}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
        ],
      ],
    );
  }
}
