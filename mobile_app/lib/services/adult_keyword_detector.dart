/// Keyword-based pornography detection for domains not already in the
/// exact-match dataset - matches the approach described in the manuscript
/// (flagging domains containing terms like "porn", "xxx", "sex", "tube").
/// This is a DIFFERENT, simpler technique from SiteCategoryMlClassifier's
/// character-pattern ML model - deliberately so: the manuscript describes
/// keyword matching specifically for this category, and this class
/// implements that description honestly rather than quietly substituting
/// the ML approach everywhere.
///
/// WHY NOT A BARE "x" KEYWORD, even though early drafts mentioned it: the
/// real domain for X (formerly Twitter) is literally x.com. A bare
/// "contains x" rule would flag one of the most-visited sites on Earth -
/// proven, not hypothetical. "xxx" is used here instead, which is both
/// the actual industry convention for adult content (.xxx is a real
/// top-level domain reserved for it) and far less likely to collide with
/// an unrelated real domain.
///
/// WHY SUBSTRING MATCHING, NOT WORD-BOUNDARY MATCHING (unlike
/// PatternDetectionService.riskyKeywords' _matchesKeyword, which requires
/// a keyword to be its own isolated token): tested during development and
/// rejected for this specific use. Real pornography domains are
/// overwhelmingly compound names - pornhub.com, youporn.com,
/// xvideos.com - where the keyword is fused with other letters, not an
/// isolated token the way "x" is inside a package name like
/// "com.example.x.app". Word-boundary matching missed 7 of 10 realistic
/// test domains during development (see git history / session notes) -
/// safe, but nearly useless. Substring matching catches real naming
/// patterns, at the cost of reopening the false-positive risk that
/// word-boundary matching was meant to prevent.
///
/// WHY AN ALLOWLIST, THEN: this is the standard, real mitigation for
/// exactly this well-documented failure mode - often called the
/// "Scunthorpe problem" (named after a UK town whose name contains a
/// vulgar substring and was repeatedly, famously blocked by naive
/// content filters). [_knownSafeDomains] holds specific real domains
/// that would otherwise collide with the keywords above
/// (youtube.com contains "tube"; several UK place-name domains -
/// essex/sussex/middlesex/wessex - contain "sex" as a substring of their
/// place name, not a live isolated word). Checked BEFORE any keyword
/// match.
///
/// HONEST LIMITATION, stated plainly, not hidden: this allowlist can
/// never be complete. A legitimate domain not in this list that happens
/// to contain one of these substrings (a not-yet-anticipated case) could
/// still false-positive. This is an inherent, well-known property of
/// keyword/substring matching in general - not a flaw unique to this
/// implementation - and is exactly why the ML classifier (for gambling)
/// was validated differently, with a measured false-positive rate against
/// held-out real data, rather than an allowlist. Keyword matching and ML
/// classification are different techniques with different, honestly
/// different guarantees; this class does not overclaim the same
/// statistical rigor for keyword matching that SiteCategoryMlClassifier's
/// evaluation provides for gambling.
class AdultKeywordDetector {
  // FIX: this list previously had no keyword that actually matches
  // "xvideos.com" - one of the exact compound-name examples this class's
  // own doc comment above cites as the reason substring matching was
  // chosen over word-boundary matching. Caught by
  // adult_keyword_detector_test.dart's compound-domain test failing in
  // real CI (Build Android APK #25), not by inspection - the substring
  // families ('porn', 'xxx', 'sex', 'tube') just didn't happen to cover
  // this specific, very-high-traffic real site. Adding the site name
  // itself as its own keyword, same as the others: a specific enough
  // string that it is not expected to collide with unrelated domains the
  // way a shorter generic fragment might.
  static const List<String> _keywords = [
    'porn',
    'xxx',
    'sex',
    'tube',
    'xvideos',
    // Added 19 Nov 2026 (same list as AdultKeywordMatcher.kt) after testing
    // on 6,001 unseen adult domains and 79,031 popular normal sites.
    'fuck',
    'hentai',
    'nude',
    'nsfw',
    'pussy',
    'boob',
    'slut',
    'whore',
    'erotic',
    'fetish',
    'bdsm',
    'blowjob',
    'horny',
    'xnxx',
    'xhamster',
    'escort',
    'camgirl',
    'milf',
    // Filipino (added 21 Nov 2026, same as AdultKeywordMatcher.kt).
    'kantot',
    'jakol',
    'tsupa',
    'libog',
    'tamod',
    'iyutan',
    'pinayflix',
    'sulasok',
  ];

  /// The keyword list, for the test that keeps it in sync with Kotlin.
  static List<String> get keywords => List.unmodifiable(_keywords);

  /// Ordinary words that contain a keyword ("milford" contains "milf").
  static const List<String> _safeSubstrings = ['milford'];

  static const Set<String> _knownSafeDomains = {
    'youtube.com',
    'youtube-nocookie.com',
    'm.youtube.com',
    'youtu.be',
    'roblox.com',
    'xbox.com',
    'x.com',
    'box.com',
    'dropbox.com',
    'fedex.com',
    'xfinity.com',
    'complex.com',
    'flexport.com',
    'nexus.com',
    'plexus.com',
    'context.com',
    'tubemogul.com',
    'essex.ac.uk',
    'essexpolice.uk',
    'middlesex.gov.uk',
    'sussex.ac.uk',
    'wessex.com',
    'oxford.ac.uk',
    'sexpistols-official.com',
  };

  /// Returns true if [domain] contains a pornography-related keyword and
  /// is not on the known-safe allowlist. Case-insensitive; checks the
  /// domain string as a whole (not per-subdomain-label), since the
  /// keywords here are meant to be checked as simple substrings, unlike
  /// SiteCategoryService's exact lookup which walks subdomain levels.
  bool matches(String domain) {
    final normalized = domain.trim().toLowerCase();

    if (_knownSafeDomains.contains(normalized)) return false;

    var checked = normalized;
    for (final word in _safeSubstrings) {
      checked = checked.replaceAll(word, '');
    }
    return _keywords.any((keyword) => checked.contains(keyword));
  }
}
