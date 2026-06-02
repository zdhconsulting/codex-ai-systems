@echo off
setlocal
cd /d "%~dp0"

where pythonw >nul 2>nul
if %errorlevel%==0 (
  start "" pythonw "%~dp0cpu_memory_widget.pyw"
  exit /b
)

where python >nul 2>nul
if %errorlevel%==0 (
  start "" python "%~dp0cpu_memory_widget.pyw"
  exit /b
)

echo Python was not found.
echo Install Python from https://www.python.org/downloads/windows/
echo During installation, check "Add python.exe to PATH".
pause
