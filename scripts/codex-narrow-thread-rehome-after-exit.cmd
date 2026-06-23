@echo off
wscript.exe //B //Nologo "%~dp0run-hidden-powershell.vbs" "%~dp0codex-narrow-thread-rehome-after-exit.ps1" %*
