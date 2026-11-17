import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/site_category_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Website domain validation', () {
    test('accepts a valid domain', () {
      expect(WebsiteRules.normalizeDomain('example.com'), 'example.com');
    });

    test('normalizes uppercase letters and whitespace', () {
      expect(WebsiteRules.normalizeDomain('  EXAMPLE.COM  '), 'example.com');
    });

    test('extracts domain from a complete URL', () {
      expect(
        WebsiteRules.normalizeDomain('https://www.example.com/page?q=test'),
        'example.com',
      );
    });

    test('preserves specific subdomains', () {
      expect(
        WebsiteRules.normalizeDomain('games.example.com'),
        'games.example.com',
      );
    });

    test('rejects invalid website addresses', () {
      for (final value in [
        '',
        'example',
        'invalid domain.com',
        '*.example.com',
        'ftp://example.com',
        '-example.com',
        'example..com',
      ]) {
        expect(
          WebsiteRules.normalizeDomain(value),
          isNull,
          reason: 'Should reject $value',
        );
      }
    });
  });

  group('Website rules', () {
    test('allowed rule matches exact domain', () {
      const rules = WebsiteRules(allowedDomains: ['example.com']);

      expect(rules.isAllowed('example.com'), isTrue);
    });

    test('allowed rule matches subdomains', () {
      const rules = WebsiteRules(allowedDomains: ['example.com']);

      expect(rules.isAllowed('www.example.com'), isTrue);
      expect(rules.isAllowed('games.example.com'), isTrue);
    });

    test('does not allow unrelated domains', () {
      const rules = WebsiteRules(allowedDomains: ['example.com']);

      expect(rules.isAllowed('fakeexample.com'), isFalse);
      expect(rules.isAllowed('example.com.other.net'), isFalse);
    });

    test('allow rule takes priority over overlapping block rule', () {
      const rules = WebsiteRules(
        blockedDomains: ['example.com'],
        allowedDomains: ['games.example.com'],
      );

      expect(rules.isAllowed('games.example.com'), isTrue);
      expect(rules.isAllowed('example.com'), isFalse);
    });

    test('serializes and restores website rules', () {
      const original = WebsiteRules(
        blockedDomains: ['blocked.com'],
        allowedDomains: ['allowed.com'],
      );

      final restored = WebsiteRules.fromMap(original.toMap());

      expect(restored.blockedDomains, ['blocked.com']);
      expect(restored.allowedDomains, ['allowed.com']);
    });

    test('rejects malformed Firestore website rules', () {
      expect(
        () => WebsiteRules.fromMap({
          'blockedDomains': 'invalid',
          'allowedDomains': [],
        }),
        throwsFormatException,
      );
    });

    test('rejects rules exceeding maximum allowed domains', () {
      expect(
        () => WebsiteRules.fromMap({
          'blockedDomains': List.generate(201, (index) => 'website$index.com'),
          'allowedDomains': [],
        }),
        throwsFormatException,
      );
    });

    test('missing website rules returns empty lists', () {
      final rules = WebsiteRules.fromDocument({});

      expect(rules.blockedDomains, isEmpty);
      expect(rules.allowedDomains, isEmpty);
    });
  });

  group('Website classification override', () {
    test('guardian allow rule bypasses automatic classification', () async {
      SharedPreferences.setMockInitialValues({
        SiteCategoryService.websiteRulesCacheKey: jsonEncode({
          'childUid': 'test-child',
          'parentId': 'test-parent',
          'blockedDomains': [],
          'allowedDomains': ['example.com'],
        }),
      });

      final service = SiteCategoryService();

      final result = await service.classify('www.example.com');

      expect(result, isNull);
    });
  });
}
