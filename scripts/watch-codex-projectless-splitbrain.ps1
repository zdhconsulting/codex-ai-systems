param(
    [int]$PollSeconds = 10,
    [int]$RuntimeSeconds = 43200
)

$ErrorActionPreference = "Stop"

$StatePath = Join-Path $env:USERPROFILE ".codex\.codex-global-state.json"
$RepairScript = Join-Path $env:USERPROFILE ".codex\scripts\repair-codex-projectless-splitbrain.ps1"
$LogDir = Join-Path $env:USERPROFILE ".codex\logs\state-steward"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogPath = Join-Path $LogDir ("projectless-splitbrain-watch-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

function Write-Log {
    param([string]$Message)
    $line = ([datetimeoffset](Get-Date)).ToString("o") + " " + $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Get-BadSplitbrainCount {
    $raw = Get-Content -LiteralPath $StatePath -Raw
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    $state = $raw | ConvertFrom-Json
    $count = 0
    foreach ($threadId in @($state.'projectless-thread-ids')) {
        $hint = $state.'thread-workspace-root-hints'.$threadId
        $output = $state.'thread-projectless-output-directories'.$threadId
        $hasHint = ($null -ne $hint -and -not [string]::IsNullOrWhiteSpace([string]$hint))
        $hasOutput = ($null -ne $output -and -not [string]::IsNullOrWhiteSpace([string]$output))
        if ($hasHint -and -not $hasOutput) {
            $count++
        }
    }
    return $count
}

Write-Log "Starting projectless split-brain watcher for $RuntimeSeconds seconds."
$deadline = (Get-Date).AddSeconds($RuntimeSeconds)
$lastWrite = $null

while ((Get-Date) -lt $deadline) {
    try {
        $item = Get-Item -LiteralPath $StatePath
        if ($null -eq $lastWrite -or $item.LastWriteTimeUtc -ne $lastWrite) {
            $lastWrite = $item.LastWriteTimeUtc
            $badCount = Get-BadSplitbrainCount
            if ($badCount -gt 0) {
                Write-Log "Detected $badCount bad split-brain projectless entries; repairing."
                $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $RepairScript
                Write-Log $output
            }
        }
    } catch {
        Write-Log ("Watcher error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSeconds
}

Write-Log "Watcher finished."
