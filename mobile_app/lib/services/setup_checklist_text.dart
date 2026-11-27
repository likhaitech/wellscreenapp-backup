/// Text on the child's setup checklist and pairing card. Pure so it can be
/// unit tested; ChildHomeScreen shows it.
class SetupChecklistText {
  SetupChecklistText._();

  static String usageAccess(bool? granted) => granted == true
      ? 'Allowed. Screen time is read from this phone.'
      : 'Needed to show real screen time and app usage.';

  static String accessibility(bool? enabled) => enabled == true
      ? 'On. Restricted apps and websites are blocked.'
      : 'Needed to block restricted apps. Switch WellScreen on in '
            'Android Accessibility settings.';

  static String battery(bool? unrestricted) => unrestricted == true
      ? 'Allowed. Battery saver will not stop WellScreen.'
      : 'Set WellScreen to "Not optimized" / "Unrestricted" so '
            'battery saver does not stop protection.';

  static String uninstallProtection(bool? active) => active == true
      ? 'On. WellScreen cannot be uninstalled without turning '
            'this off, and your guardian is told.'
      : 'Optional. Stops WellScreen from being uninstalled '
            'without your guardian knowing.';

  static const String pairedWithParent = 'Paired with your guardian';

  static const String smsPermissionOff =
      'Off. Grant SMS permission so a backup text alert can reach your '
      'guardian even without internet, when a restricted app is opened.';

  static const String gpsShared =
      'Current GPS location shared to guardian dashboard.';
}

/// The six-digit pairing code inside a scanned QR payload, or null.
/// The guardian's QR holds the plain code; anything that is not a digit is
/// ignored.
String? pairingCodeFromQr(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 6 ? digits : null;
}
