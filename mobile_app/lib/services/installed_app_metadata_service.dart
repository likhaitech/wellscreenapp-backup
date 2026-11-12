import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Looks up user-facing Android labels and installed icons by PACKAGE NAME.
/// PackageName remains the join key for every usageDurationMs value.
class InstalledAppMetadataService {
  const InstalledAppMetadataService();

  static const MethodChannel _channel = MethodChannel('wellscreen/apps');

  Future<Map<String, Map<String, String>>> lookup(
    Iterable<String> packageNames,
  ) async {
    final packages = packageNames.where((pkg) => pkg.isNotEmpty).toSet().toList();
    if (packages.isEmpty) return {};

    try {
      final metadata = <String, Map<String, String>>{};
      // Batch lookups to keep MethodChannel messages small even for devices
      // with hundreds of used apps (no arbitrary app-count cutoff).
      for (var index = 0; index < packages.length; index += 80) {
        final end = index + 80 < packages.length ? index + 80 : packages.length;
        final response = await _channel.invokeMapMethod<String, dynamic>(
          'getUsageAppMetadata',
          {'packages': packages.sublist(index, end)},
        );
        if (response == null) continue;
        for (final entry in response.entries) {
          if (entry.value is! Map) continue;
          final raw = Map<Object?, Object?>.from(entry.value as Map);
          final label = raw['displayName'];
          final icon = raw['iconBase64'];
          metadata[entry.key] = {
            'displayName': label is String && label.trim().isNotEmpty
                ? label.trim()
                : entry.key,
            if (icon is String && icon.isNotEmpty) 'iconBase64': icon,
          };
        }
      }
      return metadata;
    } on PlatformException catch (error) {
      debugPrint('Installed app metadata lookup failed: $error');
      return {};
    } on MissingPluginException catch (error) {
      debugPrint('Android app metadata method unavailable: $error');
      return {};
    }
  }
}
