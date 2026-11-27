import 'package:app/services/guardian_activity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes once, then waits for the gap before writing again', () async {
    final writes = <String>[];
    var now = DateTime(2026, 11, 21, 9, 0);
    final service = GuardianActivityService(
      write: (uid) async => writes.add(uid),
      currentUid: () => 'g1',
      clock: () => now,
    );

    expect(await service.markActive(), isTrue);
    now = now.add(const Duration(minutes: 5));
    expect(await service.markActive(), isFalse);
    now = now.add(const Duration(minutes: 6));
    expect(await service.markActive(), isTrue);
    expect(writes, ['g1', 'g1']);
  });

  test('a different guardian on the same phone is written right away',
      () async {
    final writes = <String>[];
    var uid = 'g1';
    final service = GuardianActivityService(
      write: (u) async => writes.add(u),
      currentUid: () => uid,
      clock: () => DateTime(2026, 11, 21, 9, 0),
    );
    await service.markActive();
    uid = 'g2';
    await service.markActive();
    expect(writes, ['g1', 'g2']);
  });

  test('signed out or a failed write does nothing and does not throw',
      () async {
    final signedOut = GuardianActivityService(
      write: (_) async => fail('should not write'),
      currentUid: () => null,
    );
    expect(await signedOut.markActive(), isFalse);

    var calls = 0;
    final failing = GuardianActivityService(
      write: (_) async {
        calls++;
        throw Exception('offline');
      },
      currentUid: () => 'g1',
    );
    expect(await failing.markActive(), isFalse);
    // The failure is not remembered as a write, so the next call retries.
    expect(await failing.markActive(), isFalse);
    expect(calls, 2);
  });
}
