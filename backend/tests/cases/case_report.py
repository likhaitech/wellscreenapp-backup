"""Shared output for the Chapter 4 backend test cases (one file per case).

Prints the same block as the Flutter and Kotlin cases:

    PASS  backend/tests/cases/test_pairing_service_case_033.py
      Test Case ID: CASE-033
      Code tested: backend/app/services/pairing_service.py
      ✓ Test Case Description: ... | Expected Result: ...
    Actual Result: ... | Outcome: PASSED (12 ms)

    Tests:       1 passed, 0 failed, 1 total
    Time:        0.01 s

Run with -s so pytest shows the printout.
"""
from __future__ import annotations

import time
from typing import Callable


def run_case(
    case_id: str,
    *,
    file: str,
    code_tested: str,
    description: str,
    expected: str,
    body: Callable[[], str],
) -> None:
    start = time.perf_counter()
    try:
        actual = body()
    except BaseException as error:  # print the failure, then fail the test
        ms = int((time.perf_counter() - start) * 1000)
        print(f"\nFAIL  {file}\n  Test Case ID: {case_id}\n  Code tested: {code_tested}")
        print(f"  ✗ Test Case Description: {description} | Expected Result: {expected}")
        print(f"Actual Result: {error!r} | Outcome: FAILED ({ms} ms)\n")
        print(f"Tests:       0 passed, 1 failed, 1 total\nTime:        {ms / 1000:.2f} s")
        raise
    ms = int((time.perf_counter() - start) * 1000)
    print(f"\nPASS  {file}\n  Test Case ID: {case_id}\n  Code tested: {code_tested}")
    print(f"  ✓ Test Case Description: {description} | Expected Result: {expected}")
    print(f"Actual Result: {actual} | Outcome: PASSED ({ms} ms)\n")
    print(f"Tests:       1 passed, 0 failed, 1 total\nTime:        {ms / 1000:.2f} s")
