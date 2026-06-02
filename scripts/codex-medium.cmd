@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\scripts\codex-auto.ps1" [medium] %*
