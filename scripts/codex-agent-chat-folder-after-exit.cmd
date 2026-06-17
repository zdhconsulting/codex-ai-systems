@echo off
start "Codex named agent folder after exit" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-agent-chat-folder-after-exit.ps1" %*
