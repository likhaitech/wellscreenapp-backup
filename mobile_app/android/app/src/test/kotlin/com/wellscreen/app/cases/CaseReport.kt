package com.wellscreen.app.cases

/**
 * Shared output for the Chapter 4 test cases written in Kotlin - the same
 * format as the Flutter cases (test/cases/case_report.dart):
 *
 *   PASS  CaseXXX file
 *     Test Case ID: CASE-026
 *     Code tested: .../SiteBlocker.kt
 *     ✓ Test Case Description: ... | Expected Result: ...
 *   Actual Result: ... | Outcome: PASSED (3 ms)
 *
 *   Tests:       1 passed, 0 failed, 1 total
 *
 * [body] runs the REAL app code, checks it with JUnit asserts, and returns
 * the Actual Result. A failed check prints FAIL / FAILED and fails the test.
 */
fun testCase(
    id: String,
    file: String,
    codeTested: String,
    description: String,
    expected: String,
    body: () -> String,
) {
    val start = System.currentTimeMillis()
    val actual: String
    try {
        actual = body()
    } catch (e: Throwable) {
        report(file, id, codeTested, description, expected, "Check failed: ${e.message}", false, start)
        throw e
    }
    report(file, id, codeTested, description, expected, actual, true, start)
}

private fun report(
    file: String, id: String, codeTested: String, description: String,
    expected: String, actual: String, passed: Boolean, start: Long,
) {
    val ms = System.currentTimeMillis() - start
    println()
    println("${if (passed) "PASS" else "FAIL"}  $file")
    println("  Test Case ID: $id")
    println("  Code tested: $codeTested")
    println("  ${if (passed) "✓" else "✗"} Test Case Description: $description | Expected Result: $expected")
    println("Actual Result: $actual | Outcome: ${if (passed) "PASSED" else "FAILED"} ($ms ms)")
    println()
    println("Tests:       ${if (passed) 1 else 0} passed, ${if (passed) 0 else 1} failed, 1 total")
}

const val KOTLIN_TESTS = "android/app/src/test/kotlin/com/wellscreen/app/cases"
const val KOTLIN_MAIN = "android/app/src/main/kotlin/com/wellscreen/app"
