/// The name sent when a guardian generates a pairing code. The backend
/// still requires a name, but the guardian no longer types one: the child's
/// own account Full Name replaces it once the phone is paired.
const String pairingPlaceholderChildName = 'Child';

/// The name to show for a child profile: the Full Name from the child's own
/// account (synced by the child app as `childDisplayName`), then a name a
/// guardian typed on an older pairing, then [fallback].
String childNameOf(Map<String, dynamic>? data, {String fallback = 'Child'}) {
  final display = (data?['childDisplayName'] ?? '').toString().trim();
  if (display.isNotEmpty) return display;
  final typed = (data?['name'] ?? '').toString().trim();
  if (typed.isNotEmpty && typed != pairingPlaceholderChildName) return typed;
  return fallback;
}
