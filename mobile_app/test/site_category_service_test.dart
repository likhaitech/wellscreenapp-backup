import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/site_category_service.dart';

/// Covers SiteCategoryService - the three-mechanism orchestrator (exact
/// lookup -> keyword match -> ML fallback) described in its own doc
/// comment. This had no test coverage even though all three of its
/// components are now individually tested
/// (site_category_ml_classifier_test.dart, adult_keyword_detector_test.dart,
/// and the real bundled cleaned_site_categories.csv lookup table) - what
/// hadn't been checked is the ORDER and short-circuiting between them,
/// which is exactly where a real bug could hide even with each mechanism
/// individually correct (e.g. keyword matching running before the exact
/// lookup, or the ML fallback firing even when a cheaper mechanism
/// already found an answer).
///
/// Like the other ML-consumer tests, this loads the REAL bundled assets
/// (declared in pubspec.yaml) rather than mocking anything - no
/// production code changes were needed to make this testable.
///
/// IMPORTANT ABOUT THE TEST DOMAINS BELOW: cleaned_site_categories.csv
/// (59,878 rows) is essentially the same raw domain lists the ML model
/// was trained on, so almost any real-world gambling/adult domain you'd
/// reach for is ALSO a literal exact-match row - which would only ever
/// exercise the lookup path, not keyword matching or the ML fallback.
/// Every domain used to test the keyword and ML paths below was verified
/// (grep against the real bundled CSV, both directly here and
/// independently via a Python replay of the ML model) to actually be
/// absent from the exact-match dataset, so each test genuinely exercises
/// the mechanism it claims to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SiteCategoryService.classify', () {
    final service = SiteCategoryService();

    test(
      'a domain in the exact-match dataset is found via lookup, not '
      'keyword or ML',
      () async {
        // A real row in cleaned_site_categories.csv.
        final result = await service.classify('001casino.com');
        expect(result, isNotNull);
        expect(result!.category, 'gambling');
        expect(result.source, 'lookup');
        // Lookup matches don't carry a confidence score.
        expect(result.confidence, isNull);
      },
    );

    test(
      'subdomain of an exact-match dataset domain still resolves via lookup',
      () async {
        final result = await service.classify('www.001casino.com');
        expect(result, isNotNull);
        expect(result!.source, 'lookup');
      },
    );

    test(
      'a domain matching an adult keyword but NOT in the exact-match '
      'dataset is caught by AdultKeywordDetector, tagged as "keyword"',
      () async {
        // freeporn-example.net: contains AdultKeywordDetector's "porn"
        // keyword and is a made-up name, verified absent from
        // cleaned_site_categories.csv. (youporn.com was used here before,
        // but it is now a real row in the expanded adult list, so it would
        // resolve via lookup.) This can only match via the keyword path.
        final result = await service.classify('freeporn-example.net');
        expect(result, isNotNull);
        expect(result!.category, 'adult');
        expect(result.source, 'keyword');
        expect(result.confidence, isNull);
      },
    );

    test(
      'a high-confidence ML-predicted gambling domain, absent from both '
      'the exact dataset and any adult keyword, is caught by the ML '
      'fallback, tagged as "ml" with a confidence score',
      () async {
        // megawin-vipslot888.net: independently verified via Python replay
        // of the real model weights to predict 'gambling' at ~0.9985
        // confidence, and verified absent from cleaned_site_categories.csv
        // and from AdultKeywordDetector's keyword list.
        final result = await service.classify('megawin-vipslot888.net');
        expect(result, isNotNull);
        expect(result!.source, 'ml');
        expect(result.category, 'gambling');
        expect(result.confidence, isNotNull);
        expect(result.confidence, greaterThanOrEqualTo(0.9));
      },
    );

    test(
      'an ML-predicted gambling domain BELOW the confidence threshold is '
      'NOT returned at all',
      () async {
        // winbig-sportsbook.co: independently verified to predict
        // 'gambling' at only ~0.80 confidence (below the 0.90 bar), and
        // verified absent from the exact dataset and any adult keyword -
        // so this exercises the confidence gate specifically, with no
        // other mechanism able to produce a false pass.
        final result = await service.classify('winbig-sportsbook.co');
        expect(result, isNull);
      },
    );

    test(
      'a domain that predicts a non-live-deployment class (drugs) via ML '
      'is NOT returned, even above the confidence threshold',
      () async {
        // odnoklassniki.ru: the exact false positive named in the
        // training evaluation report - predicts 'drugs' at ~0.902, but
        // 'drugs' is not in liveDeploymentClasses, so
        // SiteCategoryMlClassifier.meetsDeploymentBar is false and this
        // orchestrator must return null rather than surfacing it.
        final result = await service.classify('odnoklassniki.ru');
        expect(result, isNull);
      },
    );

    test('an ordinary, unrelated domain returns null', () async {
      // Independently verified to predict 'safe' (not a harmful class at
      // all) at ~0.62 confidence.
      final result = await service.classify('anthropic.com');
      expect(result, isNull);
    });

    test('classification is case-insensitive', () async {
      final lower = await service.classify('youporn.com');
      final upper = await service.classify('YOUPORN.COM');
      expect(upper!.category, lower!.category);
      expect(upper.source, lower.source);
    });
  });
}
