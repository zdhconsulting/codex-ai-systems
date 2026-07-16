param(
    [int]$PollSeconds = 2,
    [int]$TimeoutSeconds = 86400,
    [switch]$NoRelaunch
)

$ErrorActionPreference = "Stop"

$ScriptPath = Join-Path $env:USERPROFILE ".codex\scripts\repair-codex-projectless-splitbrain.ps1"
$LogDir = Join-Path $env:USERPROFILE ".codex\logs\state-steward"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogPath = Join-Path $LogDir ("projectless-splitbrain-after-exit-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

function Write-Log {
    param([string]$Message)
    $line = ([datetimeoffset](Get-Date)).ToString("o") + " " + $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
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

$codexPath = $null
$first = Get-CodexDesktopProcess | Select-Object -First 1
if ($first -and $first.Path) {
    $codexPath = $first.Path
}

Write-Log "Waiting for Codex Desktop processes to exit."
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -eq 0) {
        break
    }
    Start-Sleep -Seconds $PollSeconds
}

$remaining = @(Get-CodexDesktopProcess)
if ($remaining.Count -gt 0) {
    Write-Log "Timed out waiting for Codex Desktop to exit; not repairing while Desktop may overwrite state."
    exit 2
}

Write-Log "Codex Desktop exited. Running projectless split-brain repair."
$repairOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
Write-Log $repairOutput

if (-not $NoRelaunch) {
    if ($codexPath -and (Test-Path -LiteralPath $codexPath)) {
        Write-Log "Relaunching Codex Desktop from $codexPath"
        Start-Process -FilePath $codexPath | Out-Null
    } else {
        Write-Log "Codex path unavailable; repair complete but relaunch skipped."
    }
}
