import 'package:app/services/admin_users_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adminPairingFromUserDocs', () {
    test('a guardian is paired when a child account points to them', () {
      final pairing = adminPairingFromUserDocs({
        'g1': {'role': 'parent'},
        'g2': {'role': 'parent'},
        'c1': {'role': 'child', 'pairedParentId': 'g1'},
        'c2': {'role': 'child', 'pairingStatus': 'not_paired'},
        'a1': {'role': 'admin'},
      });
      expect(pairing['g1'], isTrue);
      expect(pairing['g2'], isFalse);
      expect(pairing['c1'], isTrue);
      expect(pairing['c2'], isFalse);
      expect(pairing.containsKey('a1'), isFalse);
    });
  });
}
