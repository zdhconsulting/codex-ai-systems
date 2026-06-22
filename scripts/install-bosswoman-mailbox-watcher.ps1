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
$hiddenLauncher = Join-Path $repoRoot "scripts\run-hidden-powershell.vbs"

if (-not (Test-Path -LiteralPath $tickScript)) {
    throw "Tick script not found: $tickScript"
}
if (-not (Test-Path -LiteralPath $hiddenLauncher)) {
    throw "Hidden launcher not found: $hiddenLauncher"
}

$args = @(
    "`"$hiddenLauncher`"",
    "`"$tickScript`"",
    "-MaxPackets", "1",
    "-BossmanRepo", "`"$BossmanRepo`""
)

if ($LaunchCodex) {
    $args += "-LaunchCodex"
}

$taskCommand = "wscript.exe " + ($args -join " ")
& schtasks.exe /Create /TN $TaskName /TR $taskCommand /SC MINUTE /MO $EveryMinutes /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "schtasks.exe failed to create $TaskName with exit code $LASTEXITCODE"
}

$task = Get-ScheduledTask -TaskName $TaskName
$task.Settings.Hidden = $true
$task.Settings.MultipleInstances = "IgnoreNew"
$task.Settings.ExecutionTimeLimit = "PT15M"
$task | Set-ScheduledTask | Out-Null
Enable-ScheduledTask -TaskName $TaskName | Out-Null

[pscustomobject]@{
    task_name = $TaskName
    every_minutes = $EveryMinutes
    launch_codex = [bool]$LaunchCodex
    tick_script = $tickScript
    launcher = $hiddenLauncher
    bossman_repo = $BossmanRepo
    status = "installed"
} | ConvertTo-Json -Depth 5
