// CASE-037 - Rule-Based Pattern Detection and Risk Level
// Gambling website-name AI is run on 200 unseen safe domains at 0.90.
// Code being tested: lib/services/site_category_ml_classifier.dart - the
// app's real model (assets) is run on EVERY domain in
// ml/site_category/validation/safe_domains_heldout.txt.
//
// Run: flutter test test/cases/site_category_ml_classifier_case_037_test.dart -r expanded

import 'dart:io';

import 'package:app/services/site_category_ml_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testCase(
    'CASE-037',
    file: 'test/cases/site_category_ml_classifier_case_037_test.dart',
    codeTested: 'lib/services/site_category_ml_classifier.dart',
    description:
        'Gambling website-name AI is run on 200 unseen safe domains at the '
        '0.90 confidence threshold.',
    expected: 'No safe domain is flagged as gambling.',
    body: (tester) async {
      final domains = File(
        '../ml/site_category/validation/safe_domains_heldout.txt',
      )
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      expect(domains.length, 200);

      final classifier = SiteCategoryMlClassifier();
      final flagged = <String>[];
      await tester.runAsync(() async {
        for (final d in domains) {
          final r = await classifier.predict(d);
          if (r != null && r.meetsDeploymentBar && r.category == 'gambling') {
            flagged.add(d);
          }
        }
      });
      expect(flagged, isEmpty, reason: 'flagged: $flagged');
      return 'All ${domains.length} unseen safe domains were checked by the '
          'app\'s model; 0 were flagged as gambling at confidence 0.90 or '
          'higher';
    },
  );
}
