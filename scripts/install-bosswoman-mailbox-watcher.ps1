[CmdletBinding()]
param(
    [int]$EveryMinutes = 1,
    [switch]$LaunchCodex,
    [string]$BossmanRepo = "C:\Repos\bossman",
    [string]$TaskName = "ZDH Bosswoman Mailbox Watcher"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$tickScript = Join-Path $repoRoot "scripts\bosswoman-mailbox-tick.ps1"

if (-not (Test-Path -LiteralPath $tickScript)) {
    throw "Tick script not found: $tickScript"
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-WindowStyle", "Hidden",
    "-File", "`"$tickScript`"",
    "-MaxPackets", "1",
    "-BossmanRepo", "`"$BossmanRepo`""
)

if ($LaunchCodex) {
    $args += "-LaunchCodex"
}

$taskCommand = "powershell.exe " + ($args -join " ")
& schtasks.exe /Create /TN $TaskName /TR $taskCommand /SC MINUTE /MO $EveryMinutes /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "schtasks.exe failed to create $TaskName with exit code $LASTEXITCODE"
}

[pscustomobject]@{
    task_name = $TaskName
    every_minutes = $EveryMinutes
    launch_codex = [bool]$LaunchCodex
    tick_script = $tickScript
    bossman_repo = $BossmanRepo
    status = "installed"
} | ConvertTo-Json -Depth 5
