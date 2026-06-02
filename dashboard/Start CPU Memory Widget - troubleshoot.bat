@echo off
setlocal
cd /d "%~dp0"

echo Starting CPU and Memory Widget...
echo.
echo Folder: %cd%
echo.

python --version
if not %errorlevel%==0 (
  echo.
  echo Python did not start. Install Python from:
  echo https://www.python.org/downloads/windows/
  echo.
  pause
  exit /b 1
)

echo.
echo If the widget opens, you can close this window.
echo If an error appears below, send me the text.
echo.
python "%~dp0cpu_memory_widget.pyw"
pause
