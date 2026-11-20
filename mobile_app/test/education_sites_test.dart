import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/education_sites.dart';

void main() {
  group('EducationSites.isProtected', () {
    test('school, government and listed health sites are protected', () {
      for (final d in [
        'deped.gov.ph', 'up.edu.ph', 'harvard.edu', 'cdc.gov', 'who.int',
        'en.wikipedia.org', 'WWW.KidsHealth.org', 'plannedparenthood.org',
        'www.thetrevorproject.org', 'loveyourself.ph', 'amaze.org.',
      ]) {
        expect(EducationSites.isProtected(d), isTrue, reason: d);
      }
    });

    test('ordinary and look-alike sites are not protected', () {
      for (final d in [
        '', 'google.com', 'bet88.ph', 'notwikipedia.org',
        'wikipedia.org.casino.com', 'edu-casino.com', 'govbet.net',
      ]) {
        expect(EducationSites.isProtected(d), isFalse, reason: d);
      }
    });

    test('Dart and Kotlin lists are identical', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/wellscreen/app/EducationSites.kt',
      ).readAsStringSync();
      Set<String> quoted(String block) => RegExp(r'"([^"]+)"')
          .allMatches(block)
          .map((m) => m.group(1)!)
          .toSet();
      String between(String start) {
        final from = kotlin.indexOf(start);
        return kotlin.substring(from, kotlin.indexOf(')', from));
      }

      expect(quoted(between('val SUFFIXES')), EducationSites.suffixes.toSet());
      expect(quoted(between('val DOMAINS')), EducationSites.domains);
    });
  });
}
