Get-CimInstance Win32_Process |
  Where-Object {
    $_.CommandLine -match '(?i)\s-File\s+"?[^"]*codex-pinned-hotkeys\.ps1"?(\s|$)' -and
    $_.ProcessId -ne $PID
  } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

Write-Output "STOPPED Codex pinned hotkey listeners"
