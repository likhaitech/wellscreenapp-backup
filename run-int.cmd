@echo off
rem Runs the integration test for one INT case: run-int 002   (or: run-int all)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-int.ps1" %*
