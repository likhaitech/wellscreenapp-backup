import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/daily_goal.dart';
import 'package:app/services/privacy_text.dart';
import 'package:app/services/site_review_alert.dart';

const _kotlinDir = 'android/app/src/main/kotlin/com/wellscreen/app';

void main() {
  group('SiteReviewAlert.domainOf (Notifications Allow / Block)', () {
    test('review and ask-to-allow alerts give their site', () {
      expect(
        SiteReviewAlert.domainOf(
          'site_review_needed',
          {'subject': 'www.casino-example.com', 'label': 'x'},
        ),
        'casino-example.com',
      );
      expect(
        SiteReviewAlert.domainOf(
          'site_access_request',
          {'subject': 'school-example.org'},
        ),
        'school-example.org',
      );
    });

    test('other alerts and broken details give no buttons', () {
      expect(
        SiteReviewAlert.domainOf(
          'restricted_content_attempt',
          {'subject': 'casino-example.com'},
        ),
        isNull,
      );
      expect(SiteReviewAlert.domainOf('site_review_needed', null), isNull);
      expect(
        SiteReviewAlert.domainOf('site_review_needed', {'subject': 42}),
        isNull,
      );
      expect(
        SiteReviewAlert.domainOf('site_review_needed', {'subject': 'not a site'}),
        isNull,
      );
    });

    test('alert kinds match the child phone and the backend', () {
      final kotlin = File('$_kotlinDir/SiteReview.kt').readAsStringSync();
      expect(kotlin, contains('"${SiteReviewAlert.reviewKind}"'));
      expect(kotlin, contains('"${SiteReviewAlert.requestKind}"'));
      final backend = File(
        '../backend/app/services/monitoring_alerts_service.py',
      );
      if (backend.existsSync()) {
        final py = backend.readAsStringSync();
        for (final kind in SiteReviewAlert.kinds) {
          expect(py, contains('"$kind"'));
        }
      }
    });
  });

  group('Age strictness hand-off to the native check', () {
    test('the phone saves the age group where SiteReview.kt reads it', () {
      final kotlin = File('$_kotlinDir/SiteReview.kt').readAsStringSync();
      // Flutter's SharedPreferences adds the "flutter." prefix natively.
      expect(kotlin, contains('"flutter.${DailyGoal.ageGroupPrefKey}"'));
      // Only the youngest group blocks "possible risk" sites outright.
      expect(kotlin, contains('"${ChildAgeGroup.upTo6.id}"'));
      expect(kotlin, isNot(contains('"${ChildAgeGroup.age7to12.id}"')));
    });
  });

  group('Privacy wording', () {
    test('guardian text says page words are never saved or sent', () {
      const body = PrivacyText.guardianWebsiteBody;
      expect(body, contains('never saved or sent'));
      expect(body, contains('Never the full address'));
      expect(body, contains('Cloudflare'));
      expect(body, contains('only the site name'));
    });

    test('child text says the same, in plain words', () {
      expect(PrivacyText.childPageCheck, contains('never saved or sent'));
      expect(PrivacyText.childPageCheck, contains('including your guardian'));
      expect(PrivacyText.childPageCheck, contains('ask your guardian'));
      expect(PrivacyText.childWebsites, contains('not full addresses'));
    });

    test('Private DNS note names the right Cloudflare host', () {
      expect(PrivacyText.familyDnsHost, 'family.cloudflare-dns.com');
      expect(PrivacyText.familyDnsSteps, contains('does not block gambling'));
      final kotlin = File('$_kotlinDir/FamilyDnsCheck.kt').readAsStringSync();
      expect(kotlin, contains(PrivacyText.familyDnsHost));
    });
  });
}
