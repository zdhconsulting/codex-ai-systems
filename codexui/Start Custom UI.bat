@echo off
setlocal
cd /d "%~dp0"

if exist "Custom UI.exe" (
  start "" "Custom UI.exe"
  exit /b
)

start "" "http://127.0.0.1:4187/"

set "BUNDLED_PY=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if exist "%BUNDLED_PY%" (
  "%BUNDLED_PY%" server.py
) else (
  python server.py
)
