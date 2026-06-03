@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-project-rules.ps1" %*
