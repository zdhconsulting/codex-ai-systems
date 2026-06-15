param(
    [string] $CodexHome = "",
    [int] $TimeoutSeconds = 900,
    [switch] $NoRelaunch
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$logDir = Join-Path $CodexHome "logs"
$logPath = Join-Path $logDir "project-containers-after-exit.log"
$containerCmd = Join-Path $CodexHome "scripts\codex-project-containers.cmd"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string] $Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Add-Content -LiteralPath $logPath
}

function Get-CodexDesktopProcess {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            ($_.ProcessName -in @("Codex", "codex")) -and ($_.Path -match "\\WindowsApps\\OpenAI\.Codex_.*\\app\\")
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

Start-Sleep -Seconds 2
Write-Log "Codex Desktop exited; applying project containers"
$output = & $containerCmd 2>&1 | Out-String
Write-Log ($output.Trim())

$threadContainerCmd = Join-Path $CodexHome "scripts\codex-project-thread-containers.cmd"
if (Test-Path -LiteralPath $threadContainerCmd) {
    Write-Log "applying high-confidence thread container re-home"
    $threadOutput = & $threadContainerCmd 2>&1 | Out-String
    Write-Log ($threadOutput.Trim())
}

if (-not $NoRelaunch) {
    Write-Log "relaunching Codex Desktop"
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
}
