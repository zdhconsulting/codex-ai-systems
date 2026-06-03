@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-project-freshness-after-exit.ps1" %*
