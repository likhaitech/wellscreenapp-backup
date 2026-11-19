import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/adult_keyword_detector.dart';

/// Covers AdultKeywordDetector in isolation - pure logic, no platform
/// channels or Firebase involved, so unlike most of this test/ directory
/// this one has no execution caveats: what you see here is exactly what
/// `flutter test` would exercise.
///
/// The doc comment on the class explains WHY substring matching (not
/// word-boundary) was chosen and WHY the allowlist exists (the
/// "Scunthorpe problem" - youtube.com contains "tube", essex.ac.uk
/// contains "sex"). These tests pin down that both halves of that
/// tradeoff actually behave as documented: real adult-content domain
/// shapes get caught, and the specific allowlisted collisions don't.
void main() {
  group('AdultKeywordDetector.matches', () {
    final detector = AdultKeywordDetector();

    test('flags realistic compound adult-domain names', () {
      // These are the exact "keyword fused into a compound name" shapes
      // the doc comment says word-boundary matching missed.
      expect(detector.matches('pornhub.com'), isTrue);
      expect(detector.matches('youporn.com'), isTrue);
      expect(detector.matches('xvideos.com'), isTrue);
    });

    test('is case-insensitive', () {
      expect(detector.matches('PornHub.COM'), isTrue);
    });

    test('trims surrounding whitespace before matching', () {
      expect(detector.matches('  pornhub.com  '), isTrue);
    });

    test('does not flag an unrelated domain with none of the keywords', () {
      expect(detector.matches('wikipedia.org'), isFalse);
      expect(detector.matches('anthropic.com'), isFalse);
    });

    group('allowlist overrides keyword collisions (Scunthorpe problem)', () {
      test('youtube.com is not flagged despite containing "tube"', () {
        expect(detector.matches('youtube.com'), isFalse);
        expect(detector.matches('m.youtube.com'), isFalse);
        expect(detector.matches('youtu.be'), isFalse);
      });

      test('x.com is not flagged (no bare "x" keyword is used)', () {
        expect(detector.matches('x.com'), isFalse);
      });

      test(
        'UK place-name domains are not flagged despite containing "sex"',
        () {
          expect(detector.matches('essex.ac.uk'), isFalse);
          expect(detector.matches('sussex.ac.uk'), isFalse);
          expect(detector.matches('middlesex.gov.uk'), isFalse);
          expect(detector.matches('wessex.com'), isFalse);
        },
      );

      test('allowlist check is also case-insensitive', () {
        expect(detector.matches('YouTube.com'), isFalse);
      });
    });

    test(
      'a domain not on the allowlist that merely resembles one is still flagged',
      () {
        // Confidence check that the allowlist is doing exact matching, not
        // some fuzzy "close enough" comparison - a lookalike domain must
        // still go through normal keyword matching.
        expect(detector.matches('youtube-mirror-sex.com'), isTrue);
      },
    );
  });

  test('flags the added explicit keywords and keeps ordinary words open', () {
    final detector = AdultKeywordDetector();
    expect(detector.matches('free-hentai-site.net'), isTrue);
    expect(detector.matches('xnxx.com'), isTrue);
    expect(detector.matches('nsfwclips.example'), isTrue);
    expect(detector.matches('milfordschools.org'), isFalse);
    expect(detector.matches('googleanalytics.com'), isFalse);
    expect(detector.matches('nakedwines.com'), isFalse);
  });
}
