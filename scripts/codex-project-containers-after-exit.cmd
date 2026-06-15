@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-project-containers-after-exit.ps1" %*
