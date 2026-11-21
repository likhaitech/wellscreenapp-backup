// CASE-124 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/usage_dashboard_view_model_service_case_124_test.dart -r expanded

import 'package:app/services/child_location_text.dart';
import 'package:app/services/guardian_dashboard_text.dart';
import 'package:app/services/intervention_recommendation_service.dart';
import 'package:app/services/usage_dashboard_service.dart';
import 'package:app/services/usage_dashboard_view_model_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-124',
    file: 'test/cases/usage_dashboard_view_model_service_case_124_test.dart',
    codeTested: 'lib/services/usage_dashboard_view_model_service.dart',
    description: 'Guardian opens the dashboard with a paired child.',
    expected: 'Screen time today, protection status, top apps, safety status, last seen, and location are shown.',
    body: (tester) async {
      final report = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({
          'com.google.android.youtube': 3600000,
          'com.zhiliaoapp.musically': 1200000,
        }),
      );
      final view = UsageDashboardViewModelService().buildViewModel(
        UsageDashboardResult(
          hasUsagePermission: true,
          isUsingCachedData: false,
          report: report,
          interventionRecommendation:
              InterventionRecommendationService().getRecommendation(report),
          errorMessage: null,
        ),
      );
      final child = <String, dynamic>{
        'pairingStatus': 'connected',
        'accessibilityEnabled': true,
        'latestLocation': {'label': 'Lahug, Cebu City'},
        'locationUpdatedAt': Timestamp.fromDate(DateTime(2026, 11, 22, 8, 10)),
      };
      expect(view.totalUsageLabel, isNotEmpty);
      expect(view.topUsedAppLabel, contains('Youtube'));
      expect(protectionStatusLabels(child), ['Protection on']);
      expect(locationTextOf(child), 'Lahug, Cebu City');
      return 'Dashboard: screen time "${view.totalUsageLabel}", top app '
          '"${view.topUsedAppLabel}", safety "${view.statusLabel}", protection '
          '"${protectionStatusLabels(child).join(', ')}", location '
          '"${locationTextOf(child)}" at ${locationUpdatedTextOf(child)}';
    },
  );
}
