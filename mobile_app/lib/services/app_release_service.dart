import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the admin's system patch asks of every phone
/// (system_settings/global, written only by the backend).
class AppReleaseStatus {
  const AppReleaseStatus({
    required this.minimumVersion,
    required this.maintenanceMessage,
  });

  static const AppReleaseStatus none = AppReleaseStatus(
    minimumVersion: '1.0.0',
    maintenanceMessage: '',
  );

  final String minimumVersion;
  final String maintenanceMessage;

  factory AppReleaseStatus.fromSettings(Map<String, dynamic>? data) {
    final minimum = data?['minimum_app_version'];
    final message = data?['maintenance_message'];
    return AppReleaseStatus(
      minimumVersion: minimum is String && AppReleaseService.isVersion(minimum)
          ? minimum
          : none.minimumVersion,
      maintenanceMessage: message is String ? message.trim() : '',
    );
  }
}

class AppReleaseService {
  AppReleaseService._();

  static final RegExp _version = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$');

  static bool isVersion(String value) => _version.hasMatch(value);

  /// Negative when [a] is older than [b], 0 when equal, positive when newer.
  /// "1.10.0" is newer than "1.9.0" (numbers, not text).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final x = parts(a);
    final y = parts(b);
    for (var i = 0; i < 3; i++) {
      final left = i < x.length ? x[i] : 0;
      final right = i < y.length ? y[i] : 0;
      if (left != right) return left - right;
    }
    return 0;
  }

  static bool needsUpdate(String installed, String minimum) =>
      compareVersions(installed, minimum) < 0;

  /// This app's version from pubspec.yaml (for example "1.0.0").
  static Future<String> installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Stream<AppReleaseStatus> watch() {
    return FirebaseFirestore.instance
        .collection('system_settings')
        .doc('global')
        .snapshots()
        .map((snapshot) => AppReleaseStatus.fromSettings(snapshot.data()));
  }
}
