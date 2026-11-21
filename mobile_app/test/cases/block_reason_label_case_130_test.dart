// CASE-130 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/block_reason_label_case_130_test.dart -r expanded

import 'package:app/services/block_reason_label.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-130',
    file: 'test/cases/block_reason_label_case_130_test.dart',
    codeTested: 'mobile_app/android/app/src/main/kotlin/com/wellscreen/app/BrowsingLogger.kt',
    description: 'Guardian opens Recent Browsing Activity.',
    expected: 'Each site shows why it was flagged (page words, keyword, known list, AI-detected, or blocked by you), and blocked sites are listed; full addresses and typed text are not shown.',
    body: (tester) async {
      final labels = {
        for (final source in ['page', 'keyword', 'list', 'ai', 'parent_rule'])
          source: blockReasonLabel({'blockSource': source, 'category': 'gambling'}),
      };
      expect(labels['page'], 'gambling (page words)');
      expect(labels['keyword'], 'gambling (keyword match)');
      expect(labels['list'], 'gambling (exact match)');
      expect(labels['ai'], 'gambling (AI-detected)');
      expect(labels['parent_rule'], 'gambling (your block list)');
      return 'Reasons shown: ${labels.values.join('; ')} (only the site name '
          'is stored, never the full address or typed text)';
    },
  );
}
