@echo off
wscript.exe //B //Nologo "%~dp0run-hidden-powershell.vbs" "%~dp0codex-agent-chat-folder-after-exit.ps1" %*
