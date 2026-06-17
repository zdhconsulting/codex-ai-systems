param(
    [string] $CodexHome = "",
    [ValidateSet("watch", "ensure-running", "status")]
    [string] $Mode = "watch",
    [int] $PollSeconds = 5,
    [int] $RestartCooldownSeconds = 20
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$logDir = Join-Path $CodexHome "logs"
$logPath = Join-Path $logDir "codex-shell-steward.log"
$statePath = Join-Path $CodexHome "tmp\codex-shell-steward-state.json"
$lockPath = Join-Path $CodexHome "tmp\codex-shell-steward.lock"
$healAfterExit = Join-Path $CodexHome "scripts\codex-project-containers-after-exit.ps1"
$desktopAppId = "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$tmpDir = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
}

function Write-Utf8NoBomFile {
    param(
        [string] $Path,
        [string] $Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
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
        mode = $Mode
    }
    Write-Utf8NoBomFile -Path $lockPath -Text ($payload | ConvertTo-Json -Depth 5)
}

function Update-State {
    param(
        [string] $Status,
        [string] $Detail,
        [bool] $CodexRunning
    )

    $payload = [pscustomobject]@{
        pid = $PID
        updated_at = (Get-Date).ToString("o")
        status = $Status
        detail = $Detail
        codex_running = $CodexRunning
        log_path = $logPath
    }
    Write-Utf8NoBomFile -Path $statePath -Text ($payload | ConvertTo-Json -Depth 5)
}

function Start-CodexDesktop {
    Write-Log "launching Codex Desktop"
    Start-Process -FilePath "explorer.exe" -ArgumentList $desktopAppId -WindowStyle Hidden
}

function Invoke-HealBundle {
    if (-not (Test-Path -LiteralPath $healAfterExit)) {
        throw "Missing heal bundle: $healAfterExit"
    }
    Write-Log "running after-exit heal bundle"
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $healAfterExit -TimeoutSeconds 10 2>&1 | Out-String
    Write-Log ($output.Trim())
}

if ($Mode -eq "status") {
    if (Test-Path -LiteralPath $statePath) {
        Get-Content -Raw -LiteralPath $statePath
    } else {
        [pscustomobject]@{
            status = "unknown"
            detail = "no codex shell steward state file"
            codex_running = (@(Get-CodexDesktopProcess).Count -gt 0)
            log_path = $logPath
        } | ConvertTo-Json -Depth 5
    }
    exit 0
}

$existingLock = Get-LockOwner
if ($existingLock -and [int]$existingLock.pid -ne $PID) {
    $msg = "another Codex Shell Steward is already active (pid $($existingLock.pid))"
    Update-State -Status "already_running" -Detail $msg -CodexRunning (@(Get-CodexDesktopProcess).Count -gt 0)
    Write-Log $msg
    exit 0
}

Set-LockOwner

if ($Mode -eq "ensure-running") {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -eq 0) {
        Update-State -Status "healing" -Detail "Codex not running; launching." -CodexRunning $false
        Start-CodexDesktop
        Start-Sleep -Seconds 2
    }
    $runningNow = (@(Get-CodexDesktopProcess).Count -gt 0)
    Update-State -Status "healthy" -Detail "ensure-running completed" -CodexRunning $runningNow
    exit 0
}

$lastHealAt = [datetime]::MinValue
Write-Log "watch mode started"

while ($true) {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -gt 0) {
        Update-State -Status "healthy" -Detail "Codex Desktop running" -CodexRunning $true
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    $secondsSinceHeal = if ($lastHealAt -eq [datetime]::MinValue) {
        [double]::PositiveInfinity
    } else {
        ((Get-Date) - $lastHealAt).TotalSeconds
    }

    if ($secondsSinceHeal -lt $RestartCooldownSeconds) {
        Update-State -Status "cooldown" -Detail "waiting $([math]::Ceiling($RestartCooldownSeconds - $secondsSinceHeal))s before next relaunch attempt" -CodexRunning $false
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    try {
        Update-State -Status "healing" -Detail "Codex Desktop missing; running repair and relaunch." -CodexRunning $false
        $lastHealAt = Get-Date
        Invoke-HealBundle
        Update-State -Status "healthy" -Detail "repair bundle completed" -CodexRunning (@(Get-CodexDesktopProcess).Count -gt 0)
    } catch {
        $message = $_.Exception.Message
        Write-Log "heal failed: $message"
        Update-State -Status "error" -Detail $message -CodexRunning $false
    }

    Start-Sleep -Seconds $PollSeconds
}
