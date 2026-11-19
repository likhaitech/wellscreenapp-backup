import 'package:app/utils/child_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the child account Full Name first', () {
    expect(
      childNameOf({'childDisplayName': 'Juan Dela Cruz', 'name': 'Juan'}),
      'Juan Dela Cruz',
    );
  });

  test('keeps a name a guardian typed on an older pairing', () {
    expect(childNameOf({'name': 'Ana'}), 'Ana');
  });

  test('never shows the pairing placeholder as a real name', () {
    expect(
      childNameOf({'name': pairingPlaceholderChildName}, fallback: 'Your child'),
      'Your child',
    );
    expect(childNameOf(null, fallback: 'Child Device'), 'Child Device');
    expect(childNameOf({'childDisplayName': '  ', 'name': ''}), 'Child');
  });
}
