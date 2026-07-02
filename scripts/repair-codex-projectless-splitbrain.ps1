param(
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

$StatePath = Join-Path $env:USERPROFILE ".codex\.codex-global-state.json"
$LogDir = Join-Path $env:USERPROFILE ".codex\logs\state-steward"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Read-State {
    $raw = Get-Content -LiteralPath $StatePath -Raw
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    return $raw | ConvertFrom-Json
}

function Write-State {
    param([object]$State)
    $json = $State | ConvertTo-Json -Depth 100 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($StatePath, $json, $utf8)
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$state = Read-State
$projectless = @($state.'projectless-thread-ids')
$hints = $state.'thread-workspace-root-hints'
$outputs = $state.'thread-projectless-output-directories'

$removed = New-Object System.Collections.Generic.List[string]
$kept = New-Object System.Collections.Generic.List[string]

foreach ($threadId in $projectless) {
    $hint = $hints.$threadId
    $output = $outputs.$threadId
    $hasHint = ($null -ne $hint -and -not [string]::IsNullOrWhiteSpace([string]$hint))
    $hasOutput = ($null -ne $output -and -not [string]::IsNullOrWhiteSpace([string]$output))

    if ($hasHint -and -not $hasOutput) {
        [void]$removed.Add([string]$threadId)
    } else {
        [void]$kept.Add([string]$threadId)
    }
}

if (-not $NoBackup) {
    Copy-Item -LiteralPath $StatePath -Destination "$StatePath.bak-projectless-splitbrain-repair-$stamp" -Force
}

$state.'projectless-thread-ids' = @($kept.ToArray())
Write-State -State $state

$verify = Read-State
$bad = New-Object System.Collections.Generic.List[object]
foreach ($threadId in @($verify.'projectless-thread-ids')) {
    $hint = $verify.'thread-workspace-root-hints'.$threadId
    $output = $verify.'thread-projectless-output-directories'.$threadId
    $hasHint = ($null -ne $hint -and -not [string]::IsNullOrWhiteSpace([string]$hint))
    $hasOutput = ($null -ne $output -and -not [string]::IsNullOrWhiteSpace([string]$output))
    if ($hasHint -and -not $hasOutput) {
        [void]$bad.Add([pscustomobject]@{ thread_id = $threadId; workspace_hint = $hint })
    }
}

$aiManagerId = "019ec3de-d9cd-70e1-a8b6-6f71f1da16d4"
$ctoId = "019ecd45-a8ca-7a02-b722-215f9aafdb29"
$theaId = "019e82ad-212a-77a3-8d6c-278b5fd0c15b"

$report = [pscustomobject][ordered]@{
    repaired_at = ([datetimeoffset](Get-Date)).ToString("o")
    state_path = $StatePath
    original_projectless_count = $projectless.Count
    removed_count = $removed.Count
    remaining_projectless_count = @($verify.'projectless-thread-ids').Count
    bad_splitbrain_count = $bad.Count
    ai_manager_projectless = (@($verify.'projectless-thread-ids') -contains $aiManagerId)
    cto_projectless = (@($verify.'projectless-thread-ids') -contains $ctoId)
    thea_projectless = (@($verify.'projectless-thread-ids') -contains $theaId)
    removed_thread_ids = @($removed.ToArray())
    bad_remaining = @($bad.ToArray())
}

$reportPath = Join-Path $LogDir "projectless-splitbrain-repair-$stamp.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), $utf8)
$report | ConvertTo-Json -Depth 10
