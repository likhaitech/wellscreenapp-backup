# Runs the Chapter 4 integration test (INT-001 to INT-018) for one case,
# whatever its type (Flutter, Kotlin or backend). Usage from the project folder:
#   .\run-int 002
#   .\run-int all
param([Parameter(Mandatory = $true)][string]$Case)

$root = Split-Path -Parent $PSScriptRoot

function Run-One([int]$number) {
    $n = '{0:D3}' -f $number
    Write-Host ""
    Write-Host "===== INT-$n =====" -ForegroundColor Cyan

    $dart = "$root\mobile_app\test\integration_cases\int_${n}_test.dart"
    if (Test-Path $dart) {
        Push-Location "$root\mobile_app"
        try { flutter test "test/integration_cases/int_${n}_test.dart" -r expanded } finally { Pop-Location }
        return
    }

    $kt = "$root\mobile_app\android\app\src\test\kotlin\com\wellscreen\app\integration\Int${n}Test.kt"
    if (Test-Path $kt) {
        Push-Location "$root\mobile_app\android"
        try { .\gradlew.bat :app:testDebugUnitTest --tests "com.wellscreen.app.integration.Int${n}Test" } finally { Pop-Location }
        return
    }

    $py = "$root\backend\tests\integration_cases\test_int_${n}.py"
    if (Test-Path $py) {
        Push-Location "$root\backend"
        try { python -m pytest "tests/integration_cases/test_int_${n}.py" -s -q -p no:anyio } finally { Pop-Location }
        return
    }

    Write-Host "No integration test file found for INT-$n"
}

[Console]::OutputEncoding = [Text.Encoding]::UTF8
if ($Case -eq 'all') {
    foreach ($i in 1..18) { Run-One $i }
} else {
    Run-One ([int]$Case)
}
