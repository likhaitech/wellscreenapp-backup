// Shared output for the Chapter 4 test cases (one file per Test Case ID).
//
// Each case runs the REAL app code, checks it with expect(), and prints the
// test case the way it appears in Table 26:
//
//   Test Case ID: CASE-001
//   Test Case Description: ... | Expected Result: ...
//   Actual Result: ... | Outcome: PASSED
//
// The Actual Result is what the app really did, read back from the screen
// or the code. If any check fails, the Outcome is FAILED and the test fails.

import 'package:flutter_test/flutter_test.dart';

/// Runs one test case. [body] performs the steps, checks the result with
/// expect(), and returns the Actual Result in plain words.
void testCase(
  String id, {
  required String description,
  required String expected,
  required Future<String> Function(WidgetTester tester) body,
}) {
  testWidgets('Test Case ID: $id', (tester) async {
    final stopwatch = Stopwatch()..start();
    String actual = '(not reached)';
    try {
      actual = await body(tester);
    } catch (e) {
      _report(id, description, expected,
          actual == '(not reached)' ? 'Check failed: $e' : actual, false,
          stopwatch.elapsedMilliseconds);
      rethrow;
    }
    _report(id, description, expected, actual, true,
        stopwatch.elapsedMilliseconds);
  });
}

void _report(String id, String description, String expected, String actual,
    bool passed, int ms) {
  // ignore: avoid_print
  print('Test Case ID: $id');
  // ignore: avoid_print
  print('Test Case Description: $description | Expected Result: $expected');
  // ignore: avoid_print
  print('Actual Result: $actual | Outcome: ${passed ? 'PASSED' : 'FAILED'} '
      '($ms ms)');
}
