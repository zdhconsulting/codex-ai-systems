@echo off
setlocal
set "SCRIPT=%USERPROFILE%\.codex\hotkeys\codex-pinned-hotkeys.ps1"
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT%"
