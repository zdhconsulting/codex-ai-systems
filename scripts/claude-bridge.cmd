@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-bridge.ps1" %*
