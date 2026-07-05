$ErrorActionPreference = "Stop"

$scriptPath = "$env:USERPROFILE\.codex\hotkeys\codex-pinned-hotkeys.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit 0
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName "ZDH Codex Pinned Hotkeys" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Maps F1-F12 to the visible pinned Codex sidebar order." -Force | Out-Null
Write-Output "INSTALLED ZDH Codex Pinned Hotkeys"
