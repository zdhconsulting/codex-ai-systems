@echo off
setlocal
cd /d "%~dp0"

where pythonw >nul 2>nul
if %errorlevel%==0 (
  start "" pythonw "%~dp0zdh_dashboard.pyw"
  exit /b
)

where python >nul 2>nul
if %errorlevel%==0 (
  start "" python "%~dp0zdh_dashboard.pyw"
  exit /b
)

echo Python was not found.
pause
