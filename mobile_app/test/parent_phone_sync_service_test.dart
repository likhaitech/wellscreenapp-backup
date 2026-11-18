import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/parent_phone_sync_service.dart';

void main() {
  group('ParentPhoneSyncService.numberToStore', () {
    test('stores a newly verified number', () {
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: '+639171234567',
          storedPhone: null,
        ),
        '+639171234567',
      );
    });

    test('does nothing when the profile already has the same number', () {
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: '+639171234567',
          storedPhone: ' +639171234567 ',
        ),
        isNull,
      );
    });

    test('replaces an old number', () {
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: '+639998887777',
          storedPhone: '+639171234567',
        ),
        '+639998887777',
      );
    });

    test('asks to remove the number when none is verified any more', () {
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: null,
          storedPhone: '+639171234567',
        ),
        '',
      );
    });

    test('does nothing when there is no number anywhere', () {
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: '',
          storedPhone: null,
        ),
        isNull,
      );
    });
  });
}
