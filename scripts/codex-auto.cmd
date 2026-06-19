@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "CODEX_AUTO_CMDLINE=%CMDCMDLINE%"
set "CODEX_AUTO_STRIPPED=!CODEX_AUTO_CMDLINE:bossman-local-runner=!"
if not "!CODEX_AUTO_STRIPPED!"=="!CODEX_AUTO_CMDLINE!" if /I not "%BOSSMAN_ALLOW_DESKTOP_PROCESS_LAUNCH%"=="1" (
  echo codex-auto blocked Bossman local-runner desktop launch. Use a headless-safe runner or set BOSSMAN_ALLOW_DESKTOP_PROCESS_LAUNCH=1 intentionally. 1>&2
  exit /b 88
)
endlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-auto.ps1" %*
