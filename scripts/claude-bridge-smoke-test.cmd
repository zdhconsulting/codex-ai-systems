@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-bridge-smoke-test.ps1" %*
