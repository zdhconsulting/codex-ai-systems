@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-sidebar-reconciler.ps1" -Apply -SortByRecent -RecentPins -ArmAfterExitCleanup %*
