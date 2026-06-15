@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-thread-hygiene-after-exit.ps1" %*
