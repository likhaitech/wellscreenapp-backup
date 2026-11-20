import 'site_category_service.dart';

/// Alerts sent by the child's phone about a website the guardian decides on:
/// - site_review_needed: WellScreen wasn't sure the site is suitable (some
///   gambling/adult words on the page, or Cloudflare's family filter flagged
///   it). It was NOT blocked (except for ages 6 and below).
/// - site_access_request: the child tapped "Ask my parent to allow this
///   site" on the block screen.
/// The site name travels in the alert's details.subject (SiteReview.kt).
class SiteReviewAlert {
  SiteReviewAlert._();

  static const String reviewKind = 'site_review_needed';
  static const String requestKind = 'site_access_request';
  static const Set<String> kinds = {reviewKind, requestKind};

  /// The site this alert is about, or null for every other alert kind.
  static String? domainOf(String kind, Object? details) {
    if (!kinds.contains(kind) || details is! Map) return null;
    final subject = details['subject'];
    if (subject is! String) return null;
    return WebsiteRules.normalizeDomain(subject);
  }
}
