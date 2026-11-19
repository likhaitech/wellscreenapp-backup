/// Parses the guardian dashboard's MM/dd/yyyy HH:mm timestamp.
DateTime? parseLocationUpdatedAt(String value) {
  final match = RegExp(
    r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$',
  ).firstMatch(value.trim());

  if (match == null) return null;

  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);

  final date = DateTime(year, month, day, hour, minute);

  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute) {
    return null;
  }

  return date;
}

/// Returns a warning when the last shared GPS location is stale.
String? locationAgeWarning({
  required bool hasLocation,
  required String updatedAt,
  required DateTime now,
}) {
  if (!hasLocation) {
    return 'No location shared yet.';
  }

  final updated = parseLocationUpdatedAt(updatedAt);

  if (updated == null) {
    return 'Location update time unavailable.';
  }

  final age = now.difference(updated);

  if (age.isNegative) {
    return 'Location update time unavailable.';
  }

  // The dashboard timestamp has minute-level precision.
  if (age.inMinutes <= 60) return null;

  final hours = age.inHours;
  final unit = hours == 1 ? 'hour' : 'hours';

  return "Location is $hours $unit old - "
      "the child's app may be closed or location is off.";
}