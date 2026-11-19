import 'package:app/services/quick_block_sites.dart';
import 'package:app/services/site_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every quick-block website is a valid rule domain', () {
    for (final site in quickBlockSites) {
      expect(site.domains, isNotEmpty, reason: site.name);
      for (final domain in site.domains) {
        expect(
          WebsiteRules.normalizeDomain(domain),
          domain,
          reason: '${site.name}: $domain',
        );
      }
    }
  });

  test('blocked only when all of the app websites are blocked', () {
    final youtube = quickBlockSites.firstWhere((s) => s.name == 'YouTube');
    expect(youtube.isBlockedIn(['youtube.com']), isFalse);
    expect(youtube.isBlockedIn(['youtu.be', 'youtube.com', 'x.com']), isTrue);
    expect(youtube.isBlockedIn(const []), isFalse);
  });
}
