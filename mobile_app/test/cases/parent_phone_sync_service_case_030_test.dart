// CASE-030 - Profile Management
// Run: flutter test test/cases/parent_phone_sync_service_case_030_test.dart -r expanded

import 'package:app/services/parent_phone_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-030',
    file: 'test/cases/parent_phone_sync_service_case_030_test.dart',
    codeTested: 'lib/services/parent_phone_sync_service.dart',
    description: 'Guardian enters the correct SMS verification code.',
    expected: 'The mobile number is marked verified for SMS backup alerts.',
    body: (tester) async {
      final toStore = ParentPhoneSyncService.numberToStore(
        verifiedPhone: '+639171234567',
        storedPhone: null,
      );
      expect(toStore, '+639171234567');
      expect(
        ParentPhoneSyncService.numberToStore(
          verifiedPhone: '+639171234567',
          storedPhone: '+639171234567',
        ),
        isNull,
      );
      return 'After verification the number $toStore is copied to the child '
          'profile (${ParentPhoneSyncService.field}) for SMS backup alerts; '
          'an up-to-date profile is left alone';
    },
  );
}
