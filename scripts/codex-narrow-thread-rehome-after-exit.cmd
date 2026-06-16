@echo off
start "Codex narrow thread rehome after exit" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-narrow-thread-rehome-after-exit.ps1" %*
