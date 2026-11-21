import 'package:cloud_firestore/cloud_firestore.dart';

/// What the guardian's dashboard and Live Location show for the child's
/// last shared location. Pure so it can be unit tested.

/// "11/22/2026 08:30" for a Firestore time, otherwise "Not available".
String formatDashboardDate(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month/$day/$year $hour:$minute';
  }
  return 'Not available';
}

/// The child's last shared location from the child profile, or null.
Map<String, dynamic>? latestLocationOf(Map<String, dynamic>? data) {
  if (data == null) return null;
  final latestLocation = data['latestLocation'];
  if (latestLocation is Map<String, dynamic>) return latestLocation;
  if (latestLocation is Map) return Map<String, dynamic>.from(latestLocation);
  return null;
}

/// The address (or coordinates) of the last shared location.
String locationTextOf(Map<String, dynamic>? data) {
  final location = latestLocationOf(data);
  if (location == null) return 'No shared GPS yet';
  final label = location['label'];
  final latitude = location['latitude'];
  final longitude = location['longitude'];
  if (label != null && label.toString().isNotEmpty) return label.toString();
  if (latitude is num && longitude is num) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
  return 'No shared GPS yet';
}

/// When the last location was shared.
String locationUpdatedTextOf(Map<String, dynamic>? data) {
  if (data == null) return 'Waiting for update';
  final updatedAt = data['locationUpdatedAt'];
  if (updatedAt is Timestamp) return formatDashboardDate(updatedAt);
  return 'Waiting for update';
}
