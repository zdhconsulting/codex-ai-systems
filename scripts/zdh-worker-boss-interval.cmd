@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0zdh-worker-boss-interval.ps1" %*
