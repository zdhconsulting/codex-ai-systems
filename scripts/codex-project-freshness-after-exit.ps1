param(
    [string] $CodexHome = "",
    [int] $TimeoutSeconds = 600,
    [switch] $NoRelaunch
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$logDir = Join-Path $CodexHome "logs"
$logPath = Join-Path $logDir "project-freshness-after-exit.log"
$freshnessCmd = Join-Path $CodexHome "scripts\codex-project-freshness.cmd"
$statePath = Join-Path $CodexHome ".codex-global-state.json"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string] $Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Add-Content -LiteralPath $logPath
}

function Get-CodexDesktopProcess {
    Get-Process -Name "Codex" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -match "\\WindowsApps\\OpenAI\.Codex_.*\\app\\Codex\.exe$"
        } catch {
            $false
        }
    }
}

Write-Log "waiting for Codex Desktop to exit"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    $processes = @(Get-CodexDesktopProcess)
    if ($processes.Count -eq 0) { break }
    Start-Sleep -Seconds 1
}

$remaining = @(Get-CodexDesktopProcess)
if ($remaining.Count -gt 0) {
    Write-Log "timeout waiting for Codex Desktop to exit; remaining processes: $($remaining.Id -join ', ')"
    exit 2
}

# Give Electron a final moment to flush its own persisted atom state.
Start-Sleep -Seconds 2

Write-Log "Codex Desktop exited; applying project freshness"
$output = & $freshnessCmd 2>&1 | Out-String
Write-Log ($output.Trim())

if (Test-Path -LiteralPath $statePath) {
    $bytes = [System.IO.File]::ReadAllBytes($statePath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    Write-Log "state UTF-8 BOM present: $hasBom"
}

if (-not $NoRelaunch) {
    Write-Log "relaunching Codex Desktop"
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
}

