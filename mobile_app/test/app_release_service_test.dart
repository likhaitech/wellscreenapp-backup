import 'package:app/services/app_release_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versions compare as numbers', () {
    expect(AppReleaseService.needsUpdate('1.0.0', '1.4.0'), isTrue);
    expect(AppReleaseService.needsUpdate('1.4.0', '1.4.0'), isFalse);
    expect(AppReleaseService.needsUpdate('1.10.0', '1.9.0'), isFalse);
    expect(AppReleaseService.needsUpdate('2.0.0', '1.99.99'), isFalse);
    expect(AppReleaseService.needsUpdate('1.0.0+7', '1.0.1'), isTrue);
  });

  test('settings from the server', () {
    final status = AppReleaseStatus.fromSettings({
      'minimum_app_version': '1.4.0',
      'maintenance_message': '  Server maintenance tonight  ',
    });
    expect(status.minimumVersion, '1.4.0');
    expect(status.maintenanceMessage, 'Server maintenance tonight');
  });

  test('missing or broken settings never lock anyone out', () {
    expect(AppReleaseStatus.fromSettings(null).minimumVersion, '1.0.0');
    expect(
      AppReleaseStatus.fromSettings({'minimum_app_version': 'abc'})
          .minimumVersion,
      '1.0.0',
    );
  });
}
