/// Privacy wording for website checks, shared by the guardian's Privacy
/// Boundary sheet and the child's "Monitoring is on" sheet so both always
/// say the same thing. Must match what the code does:
/// - only the site name is recorded (BrowsingLogger), never the full address;
/// - page words are read on the child's phone by PageTextClassifier.kt and
///   dropped right away - never stored, logged or sent;
/// - only the site name goes to Cloudflare's family filter (FamilyDnsCheck.kt);
/// - alerts to the guardian carry the site name and a short reason only.
class PrivacyText {
  PrivacyText._();

  static const String guardianWebsiteTitle = 'Website names only';

  static const String guardianWebsiteBody =
      'The site name (for example, example.com) in supported browsers. '
      'Never the full address or what was typed. To catch harmful new '
      'sites, the words shown on a page are checked on the child\'s phone '
      'and forgotten right away - page content is never saved or sent, not '
      'even to you. A site\'s name may also be checked with Cloudflare\'s '
      'free family filter, which receives only the site name.';

  static const String childWebsites =
      'Names of websites you open in a supported browser (like example.com) '
      '- not full addresses or what you type.';

  static const String childPageCheck =
      'To keep you safe from gambling and adult sites, WellScreen checks the '
      'words on a web page right here on your phone. Those words are never '
      'saved or sent to anyone, including your parent. A site\'s name may '
      'also be checked with a family safety filter (Cloudflare). School and '
      'health sites are never blocked automatically, and you can ask your '
      'parent to allow a blocked site.';

  /// Optional whole-phone filter the guardian can switch on in Android
  /// settings (shown on the child's Safety tab).
  static const String familyDnsHost = 'family.cloudflare-dns.com';

  static const String familyDnsSteps =
      'Your parent can also turn on Cloudflare\'s free family filter for '
      'the whole phone: Settings > Network & internet > Private DNS > '
      'Private DNS provider hostname, then enter $familyDnsHost. It blocks '
      'adult and harmful sites in every app, not only browsers. It does not '
      'block gambling - WellScreen still does that. If it ever blocks a '
      'school or health site you need, it can be switched off the same way.';
}
