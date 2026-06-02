@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-guard.ps1" %*
