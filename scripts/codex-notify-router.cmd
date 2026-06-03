@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-notify-router.ps1" %*
