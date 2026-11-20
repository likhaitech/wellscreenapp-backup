/// Education and health sites that WellScreen's AUTOMATIC checks never block
/// (keywords, lists, gambling AI, page words, Cloudflare). A guardian's own
/// Block rule still works on them - the guardian always has the last word.
///
/// Why: a child researching sex education, puberty, HIV or LGBT topics for
/// school must not be blocked by a filter that mistakes a health page for an
/// adult one. Keep this list in sync with EducationSites.kt (a unit test
/// compares the two files).
class EducationSites {
  EducationSites._();

  /// Whole domain endings: schools and government sites.
  static const List<String> suffixes = [
    '.edu', '.edu.ph', '.gov', '.gov.ph', '.ac.uk', '.edu.au', '.int',
  ];

  /// Specific sites (and their subdomains).
  static const Set<String> domains = {
    // Encyclopedias and learning
    'wikipedia.org', 'wikimedia.org', 'wiktionary.org', 'britannica.com',
    'khanacademy.org', 'coursera.org', 'edx.org',
    // International and Philippine health bodies
    'who.int', 'unicef.org', 'unfpa.org', 'unaids.org', 'unesco.org',
    'redcross.org', 'redcross.org.ph',
    // Child and teen health
    'kidshealth.org', 'nhs.uk', 'mayoclinic.org', 'medlineplus.gov',
    'clevelandclinic.org', 'hopkinsmedicine.org', 'healthychildren.org',
    // Sex education and reproductive health
    'plannedparenthood.org', 'scarleteen.com', 'amaze.org', 'avert.org',
    'likhaan.org', 'itsyoursexlife.com',
    // HIV and LGBT support
    'loveyourself.ph', 'thetrevorproject.org', 'itgetsbetter.org',
    'glaad.org', 'pflag.org', 'stonewall.org.uk', 'hrc.org',
  };

  static bool isProtected(String domain) {
    var d = domain.trim().toLowerCase();
    while (d.endsWith('.')) {
      d = d.substring(0, d.length - 1);
    }
    if (d.startsWith('www.')) d = d.substring(4);
    if (d.isEmpty) return false;
    if (suffixes.any(d.endsWith)) return true;
    final labels = d.split('.');
    for (var start = 0; start <= labels.length - 2; start++) {
      if (domains.contains(labels.sublist(start).join('.'))) return true;
    }
    return false;
  }
}
