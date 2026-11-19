import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../utils/child_name.dart';

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

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(childName, generatedAt),
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
          _buildBrowsingSection(data),
          pw.SizedBox(height: 18),
          _buildLocationSection(data),
          pw.SizedBox(height: 18),
          _buildAlertsSection(data),
        ],
      ),
    );

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

  // -------------------------------------------------------------------
  // Section builders - mirror reports_screen.dart's four tabs (Usage,
  // Browsing, Location, Alerts) so the exported PDF matches what the
  // guardian already sees in-app, just in a form they can save or send.
  // -------------------------------------------------------------------

  static pw.Widget _buildHeader(String childName, DateTime generatedAt) {
    final formatted =
        '${generatedAt.month.toString().padLeft(2, '0')}/'
        '${generatedAt.day.toString().padLeft(2, '0')}/'
        '${generatedAt.year} '
        '${generatedAt.hour.toString().padLeft(2, '0')}:'
        '${generatedAt.minute.toString().padLeft(2, '0')}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'WellScreen Report',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '$childName  ·  Generated $formatted',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
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
                '• ${entry['packageName'] ?? 'unknown app'} · '
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
