param(
    [string] $CodexHome = "",
    [int] $TimeoutSeconds = 7200,
    [switch] $NoRelaunch
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$logDir = Join-Path $CodexHome "logs"
$logPath = Join-Path $logDir "thread-hygiene-after-exit.log"
$hygieneCmd = Join-Path $CodexHome "scripts\codex-thread-hygiene.cmd"
$sidebarReconciler = Join-Path $CodexHome "scripts\codex-sidebar-reconciler.ps1"
$stateDbCandidates = @(
    (Join-Path $CodexHome "state_5.sqlite"),
    (Join-Path $CodexHome "sqlite\state_5.sqlite")
)

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
            $path = $_.Path
            $isPackagedApp = $path -match "\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\"
            $isUnifiedDesktop = ($_.ProcessName -ieq "ChatGPT") -and ($path -match "\\app\\ChatGPT\.exe$")
            $isLegacyDesktop = ($_.ProcessName -ieq "Codex") -and ($path -match "\\app\\Codex\.exe$")
            $isPackagedApp -and ($isUnifiedDesktop -or $isLegacyDesktop)
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
Write-Log "Codex Desktop exited; applying thread hygiene"
foreach ($stateDb in $stateDbCandidates) {
    if (-not (Test-Path -LiteralPath $stateDb)) {
        Write-Log "skipping missing state db: $stateDb"
        continue
    }

    Write-Log "applying thread hygiene to $stateDb"
    $output = & $hygieneCmd -DbPath $stateDb 2>&1 | Out-String
    Write-Log ($output.Trim())
}

if (Test-Path -LiteralPath $sidebarReconciler) {
    Write-Log "applying sidebar reconciler while Codex Desktop is closed"
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sidebarReconciler -Apply -SortByRecent -RecentPins -Json 2>&1 | Out-String
    Write-Log ($output.Trim())
} else {
    Write-Log "sidebar reconciler not found; skipping sidebar state reconcile"
}

if (-not $NoRelaunch) {
    Write-Log "relaunching Codex Desktop"
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
}
