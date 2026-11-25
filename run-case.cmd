@echo off
rem Runs the test for one case: run-case 001
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-case.ps1" %*
