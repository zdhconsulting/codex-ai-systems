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
$lockPath = Join-Path $CodexHome "tmp\project-containers-after-exit.lock"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string] $Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Add-Content -LiteralPath $logPath
}

function Write-Utf8NoBomFile {
    param(
        [string] $Path,
        [string] $Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
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

function Get-LockOwner {
    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $null
    }
    try {
        $raw = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
        if (-not $raw.pid) { return $null }
        $proc = Get-Process -Id ([int]$raw.pid) -ErrorAction SilentlyContinue
        if (-not $proc) { return $null }
        return $raw
    } catch {
        return $null
    }
}

function Set-LockOwner {
    $payload = [pscustomobject]@{
        pid = $PID
        started_at = (Get-Date).ToString("o")
        timeout_seconds = $TimeoutSeconds
    }
    Write-Utf8NoBomFile -Path $lockPath -Text ($payload | ConvertTo-Json -Depth 5)
}

function Clear-LockOwner {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

$existingLock = Get-LockOwner
if ($existingLock -and [int]$existingLock.pid -ne $PID) {
    Write-Log "another project-containers-after-exit run is already active (pid $($existingLock.pid)); skipping duplicate launch"
    exit 0
}

Set-LockOwner
try {

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
if (@(Get-CodexDesktopProcess).Count -gt 0) {
    Write-Log "Codex Desktop restarted before repair phase began; skipping state mutation"
    exit 3
}

Write-Log "Codex Desktop exited; applying project containers"
$output = & $containerCmd 2>&1 | Out-String
Write-Log ($output.Trim())

$threadContainerCmd = Join-Path $CodexHome "scripts\codex-project-thread-containers.cmd"
if (Test-Path -LiteralPath $threadContainerCmd) {
    if (@(Get-CodexDesktopProcess).Count -eq 0) {
        Write-Log "applying high-confidence thread container re-home"
        $threadOutput = & $threadContainerCmd 2>&1 | Out-String
        Write-Log ($threadOutput.Trim())
    } else {
        Write-Log "skipping thread container re-home because Codex Desktop came back during repair"
    }
}

$threadHygieneCmd = Join-Path $CodexHome "scripts\codex-thread-hygiene.cmd"
if (Test-Path -LiteralPath $threadHygieneCmd) {
    if (@(Get-CodexDesktopProcess).Count -eq 0) {
        Write-Log "applying inactive/noisy thread hygiene"
        $hygieneOutput = & $threadHygieneCmd 2>&1 | Out-String
        Write-Log ($hygieneOutput.Trim())
    } else {
        Write-Log "skipping thread hygiene because Codex Desktop came back during repair"
    }
}

if (-not $NoRelaunch) {
    if (@(Get-CodexDesktopProcess).Count -eq 0) {
        Write-Log "relaunching Codex Desktop"
        Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
    } else {
        Write-Log "skipping relaunch because Codex Desktop is already running again"
    }
}
} finally {
    Clear-LockOwner
}
