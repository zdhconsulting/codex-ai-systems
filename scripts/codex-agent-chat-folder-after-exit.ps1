param(
    [string] $CodexHome = "",
    [string] $DbPath = "",
    [int] $TimeoutSeconds = 900,
    [switch] $NoRelaunch
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$logDir = Join-Path $CodexHome "logs"
$logPath = Join-Path $logDir "agent-chat-folder-after-exit.log"
$statePath = Join-Path $CodexHome ".codex-global-state.json"
$DbPath = if ($DbPath) { $DbPath } else { Join-Path $CodexHome "sqlite\state_5.sqlite" }
$folder = "C:\Users\zev\Documents\Codex\00-agent-chats"
$label = "00 AGENTS / Named Agent Chats"
$threadIds = @(
    "019ec3de-d9cd-70e1-a8b6-6f71f1da16d4",
    "019ecd45-a8ca-7a02-b722-215f9aafdb29",
    "019ecdd5-ba02-79b1-bda0-660f32c769bf",
    "019ea0a7-1056-7c00-84f1-12fa689e503c",
    "019ece0c-9a8d-7081-b8ec-c9dd4cccc845",
    "019ece22-a91f-7cb2-9458-1ff3b8c22ca1",
    "019ecd4e-c4cd-78e1-97b2-8a79a1fdf3c2",
    "019ecd6b-8f04-7990-80cc-9446db988f84",
    "019ed57c-88dc-7b93-a609-15ffde8bf6fe",
    "019ed57d-0b21-75f1-bf62-73aa21d56bc2",
    "019ed57e-cc1e-7363-8d37-67b212bfa468",
    "019ed57f-5127-78b0-a568-83606bba4ed1",
    "019ed5a7-ae7b-7601-828c-b293d0155e56"
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
            ($_.ProcessName -in @("Codex", "codex")) -and ($_.Path -match "\\WindowsApps\\OpenAI\.Codex_.*\\app\\")
        } catch {
            $false
        }
    }
}

function Add-FirstUnique {
    param(
        [object[]] $Items,
        [string] $Value
    )
    $rest = @($Items | Where-Object { $_ -ne $Value })
    return @($Value) + $rest
}

function Ensure-ObjectProperty {
    param(
        [object] $Object,
        [string] $Name
    )
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop -or $null -eq $prop.Value) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) -Force
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
Write-Log "Codex Desktop exited; applying named agent chat folder"

if (-not (Test-Path -LiteralPath $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

$raw = Get-Content -LiteralPath $statePath -Raw
$backup = "$statePath.bak-agent-chat-folder-after-exit-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $statePath -Destination $backup -Force
$state = $raw | ConvertFrom-Json

$state.'electron-saved-workspace-roots' = Add-FirstUnique -Items @($state.'electron-saved-workspace-roots') -Value $folder
$state.'project-order' = Add-FirstUnique -Items @($state.'project-order') -Value $folder

Ensure-ObjectProperty -Object $state -Name "electron-workspace-root-labels"
$state.'electron-workspace-root-labels' | Add-Member -NotePropertyName $folder -NotePropertyValue $label -Force

Ensure-ObjectProperty -Object $state -Name "project-appearances"
$state.'project-appearances' | Add-Member -NotePropertyName $folder -NotePropertyValue ([pscustomobject]@{
    color = "blue"
    marker = [pscustomobject]@{
        kind = "icon"
        icon = "folder"
    }
}) -Force

Ensure-ObjectProperty -Object $state -Name "thread-workspace-root-hints"
foreach ($threadId in $threadIds) {
    $state.'thread-workspace-root-hints' | Add-Member -NotePropertyName $threadId -NotePropertyValue $folder -Force
}

$state | Add-Member -NotePropertyName "agent-registrar-named-agent-folder" -NotePropertyValue ([pscustomobject]@{
    folder = $folder
    label = $label
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    policy = "Chat-capable named agents/managers live in this single Codex Desktop project folder; pinned remains only a shortcut."
    threadIds = $threadIds
}) -Force

$json = $state | ConvertTo-Json -Depth 100 -Compress
[System.IO.File]::WriteAllText($statePath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Log "applied named agent folder; backup: $backup"

if (Test-Path -LiteralPath $DbPath) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    foreach ($suffix in @("", "-wal", "-shm")) {
        $candidate = "$DbPath$suffix"
        if (Test-Path -LiteralPath $candidate) {
            Copy-Item -LiteralPath $candidate -Destination "$candidate.bak-agent-chat-folder-$stamp" -Force
        }
    }

    $tmpPy = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
    $idsJson = $threadIds | ConvertTo-Json -Compress
    $python = @"
import json
import sqlite3

db_path = r'''$DbPath'''
folder = r'''\\?\$folder'''
thread_ids = json.loads(r'''$idsJson''')

con = sqlite3.connect(db_path)
with con:
    for thread_id in thread_ids:
        con.execute("update threads set cwd = ? where id = ?", (folder, thread_id))
con.close()
"@
    [System.IO.File]::WriteAllText($tmpPy, $python, [System.Text.UTF8Encoding]::new($false))
    $pyCandidates = @(
        (Join-Path $CodexHome "..\..\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"),
        "C:\Users\zev\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
        "python"
    )
    $pythonExe = $null
    foreach ($candidate in $pyCandidates) {
        if ($candidate -eq "python" -or (Test-Path -LiteralPath $candidate)) {
            $pythonExe = $candidate
            break
        }
    }
    & $pythonExe $tmpPy
    if ($LASTEXITCODE -ne 0) {
        throw "SQLite thread cwd update failed with exit code $LASTEXITCODE"
    }
    Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue
    Write-Log "updated named agent thread cwd in SQLite: $DbPath"
} else {
    Write-Log "SQLite db not found; skipped thread cwd update: $DbPath"
}

if (-not $NoRelaunch) {
    Write-Log "relaunching Codex Desktop"
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
}
