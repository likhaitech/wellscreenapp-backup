import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/android_app_service.dart';

/// AndroidAppService talks to the native side purely through the
/// 'wellscreen/apps' MethodChannel (see the Kotlin implementation on the
/// Android side, not covered here). No real platform call is made: the
/// standard flutter_test pattern of installing a mock handler on the
/// TestDefaultBinaryMessenger intercepts every invokeMethod call, so this
/// only exercises AndroidAppService's own Dart-side mapping, filtering,
/// sorting, and error-swallowing - never a real Android API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('wellscreen/apps');
  final messenger =
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('AndroidAppService.getInstalledApps', () {
    test('maps native results into InstalledAppInfo, sorted by name', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getInstalledApps');
        return [
          {'appName': 'Zebra App', 'packageName': 'com.example.zebra'},
          {'appName': 'apple app', 'packageName': 'com.example.apple'},
          {'appName': 'Mango App', 'packageName': 'com.example.mango'},
        ];
      });
      final service = AndroidAppService();

      final apps = await service.getInstalledApps();

      // Case-insensitive alphabetical sort by app name.
      expect(apps.map((a) => a.appName).toList(), [
        'apple app',
        'Mango App',
        'Zebra App',
      ]);
    });

    test('filters out entries with a blank app name or package name', () async {
      final testCases = [
        {'appName': '', 'packageName': 'com.example.blank'},
        {'appName': '   ', 'packageName': 'com.example.whitespace'},
        {'appName': 'No Package', 'packageName': ''},
      ];
      messenger.setMockMethodCallHandler(channel, (call) async {
        return testCases;
      });
      final service = AndroidAppService();

      final apps = await service.getInstalledApps();

      expect(apps, isEmpty);
    });

    test('a valid entry survives alongside filtered-out ones', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return [
          {'appName': '', 'packageName': 'com.example.blank'},
          {'appName': 'Valid App', 'packageName': 'com.example.valid'},
        ];
      });
      final service = AndroidAppService();

      final apps = await service.getInstalledApps();

      expect(apps.length, 1);
      expect(apps.single.appName, 'Valid App');
      expect(apps.single.packageName, 'com.example.valid');
    });

    test('returns an empty list when the native side returns null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final service = AndroidAppService();

      final apps = await service.getInstalledApps();

      expect(apps, isEmpty);
    });

    test(
      'returns an empty list instead of throwing when the channel throws',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'UNAVAILABLE', message: 'boom');
        });
        final service = AndroidAppService();

        final apps = await service.getInstalledApps();

        expect(apps, isEmpty);
      },
    );
  });

  group('AndroidAppService.isAccessibilityServiceEnabled', () {
    test('returns the native on/off value', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invokedMethod = call.method;
        return false;
      });

      final enabled = await AndroidAppService().isAccessibilityServiceEnabled();

      expect(invokedMethod, 'isAccessibilityServiceEnabled');
      expect(enabled, isFalse);
    });

    test('returns null (unknown) when the native call fails', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });

      expect(await AndroidAppService().isAccessibilityServiceEnabled(), isNull);
    });
  });

  group('AndroidAppService settings shortcuts', () {
    test('openAccessibilitySettings invokes the right method name', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invokedMethod = call.method;
        return null;
      });
      final service = AndroidAppService();

      await service.openAccessibilitySettings();

      expect(invokedMethod, 'openAccessibilitySettings');
    });

    test('openUsageAccessSettings invokes the right method name', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invokedMethod = call.method;
        return null;
      });
      final service = AndroidAppService();

      await service.openUsageAccessSettings();

      expect(invokedMethod, 'openUsageAccessSettings');
    });
  });
}
