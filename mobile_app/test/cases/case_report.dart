// Shared output for the Chapter 4 test cases (one file per Test Case ID).
//
// Each case runs the REAL app code, checks it with expect(), and prints the
// test case the way it appears in Table 26:
//
//   PASS  test/cases/register_screen_case_001_test.dart
//     Test Case ID: CASE-001
//     Code tested: lib/screens/register_screen.dart
//     ✓ Test Case Description: ... | Expected Result: ...
//   Actual Result: ... | Outcome: PASSED (629 ms)
//
//   Tests:       1 passed, 0 failed, 1 total
//   Time:        0.63 s
//
// The Actual Result is what the app really did, read back from the screen
// or the code. If any check fails, the header says FAIL, the Outcome is
// FAILED and the test fails. The summary counts the real results.

import 'package:flutter_test/flutter_test.dart';

int _passed = 0;
int _failed = 0;
int _totalMs = 0;
bool _summaryRegistered = false;

/// Runs one test case. [file] is this test file and [codeTested] the app
/// file it checks. [body] performs the steps, checks the result with
/// expect(), and returns the Actual Result in plain words.
void testCase(
  String id, {
  required String file,
  required String codeTested,
  required String description,
  required String expected,
  required Future<String> Function(WidgetTester tester) body,
}) {
  if (!_summaryRegistered) {
    _summaryRegistered = true;
    tearDownAll(_printSummary);
  }
  testWidgets('Test Case ID: $id', (tester) async {
    final stopwatch = Stopwatch()..start();
    String actual;
    try {
      actual = await body(tester);
    } catch (e) {
      _failed++;
      _totalMs += stopwatch.elapsedMilliseconds;
      _report(file, id, codeTested, description, expected, 'Check failed: $e',
          false, stopwatch.elapsedMilliseconds);
      rethrow;
    }
    _passed++;
    _totalMs += stopwatch.elapsedMilliseconds;
    _report(file, id, codeTested, description, expected, actual, true,
        stopwatch.elapsedMilliseconds);
  });
}

void _report(String file, String id, String codeTested, String description,
    String expected, String actual, bool passed, int ms) {
  final lines = [
    '',
    '${passed ? 'PASS' : 'FAIL'}  $file',
    '  Test Case ID: $id',
    '  Code tested: $codeTested',
    '  ${passed ? '✓' : '✗'} Test Case Description: $description | '
        'Expected Result: $expected',
    'Actual Result: $actual | Outcome: ${passed ? 'PASSED' : 'FAILED'} '
        '($ms ms)',
  ];
  // ignore: avoid_print
  print(lines.join('\n'));
}

void _printSummary() {
  final total = _passed + _failed;
  final seconds = (_totalMs / 1000).toStringAsFixed(2);
  // ignore: avoid_print
  print('\nTests:       $_passed passed, $_failed failed, $total total\n'
      'Time:        $seconds s\n');
}
