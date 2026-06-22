Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command ""$env:ZDH_ALLOW_DESKTOP_PROCESS_LAUNCH='1'; & 'C:\Users\zev\OneDrive\Documents\New project 2\scripts\live-manager-tick.ps1' -MaxWorkersPerTick 2 -PushMomentumSlaMinutes 5 -EnableWorkers -AllowDesktopProcessLaunch"""
shell.Run cmd, 0, False
