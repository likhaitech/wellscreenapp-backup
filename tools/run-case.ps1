# Runs the Chapter 4 test file for one case number, whatever its type
# (Flutter, Kotlin or backend). Usage from the project folder:
#   .\run-case 001
param([Parameter(Mandatory = $true)][string]$Case)

$n = '{0:D3}' -f [int]$Case
$root = Split-Path -Parent $PSScriptRoot

$dart = Get-ChildItem "$root\mobile_app\test\cases" -Filter "*_case_${n}_test.dart" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dart) {
    Push-Location "$root\mobile_app"
    try { flutter test "test/cases/$($dart.Name)" -r expanded } finally { Pop-Location }
    return
}

$kt = Get-ChildItem "$root\mobile_app\android\app\src\test\kotlin\com\wellscreen\app\cases" -Filter "*Case${n}Test.kt" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($kt) {
    Push-Location "$root\mobile_app\android"
    try { .\gradlew.bat :app:testDebugUnitTest --tests "com.wellscreen.app.cases.$($kt.BaseName)" } finally { Pop-Location }
    return
}

$py = Get-ChildItem "$root\backend\tests\cases" -Filter "test_*_case_${n}.py" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($py) {
    Push-Location "$root\backend"
    try { python -m pytest "tests/cases/$($py.Name)" -s -q } finally { Pop-Location }
    return
}

Write-Host "No test file found for CASE-$n"
