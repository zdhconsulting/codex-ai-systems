[CmdletBinding()]
param(
    [int]$MaxPackets = 1,
    [switch]$LaunchCodex,
    [string]$BossmanRepo = "C:\Repos\bossman"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$inboxPath = Join-Path $repoRoot "controller-mailbox\inbox\ai-manager-to-bosswoman.jsonl"
$outboxPath = Join-Path $repoRoot "controller-mailbox\outbox\bosswoman-to-ai-manager.jsonl"
$stateDir = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox"
$packetDir = Join-Path $stateDir "packets"
$logDir = Join-Path $stateDir "logs"
$seenPath = Join-Path $stateDir "processed-ai-manager-packets.txt"
$lockPath = Join-Path $stateDir "watcher.lock"

New-Item -ItemType Directory -Force -Path $stateDir, $packetDir, $logDir | Out-Null
if (-not (Test-Path -LiteralPath $seenPath)) {
    New-Item -ItemType File -Force -Path $seenPath | Out-Null
}

$logPath = Join-Path $logDir ("bosswoman-mailbox-tick-{0}.log" -f (Get-Date -Format "yyyyMMdd"))

function Write-TickLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
}

function Add-OutboxPacket {
    param(
        [object]$InboxPacket,
        [string]$Status,
        [string]$Message,
        [string]$Severity = "fyi"
    )

    $timestamp = [DateTimeOffset]::UtcNow
    $reply = [ordered]@{
        packet_id = "bosswoman-watch-{0}-{1}" -f $timestamp.ToUnixTimeMilliseconds(), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
        created_at = $timestamp.ToString("o")
        from = "Bosswoman MAYHASAPC watcher"
        to = "AI Manager"
        type = "status"
        severity = $Severity
        project_scope = $InboxPacket.project_scope
        requested_action = "ai_manager_review"
        status = $Status
        message = $Message
        reply_to = $InboxPacket.packet_id
        idempotency_key = "watcher-$($InboxPacket.packet_id)-$Status"
    }

    $json = $reply | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $outboxPath -Value $json -Encoding utf8
}

$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    Write-TickLog "Another watcher tick is already running; exiting."
    exit 0
}

try {
    Write-TickLog "Tick start. LaunchCodex=$LaunchCodex"
    git -C $repoRoot pull --ff-only | Out-Null

    if (-not (Test-Path -LiteralPath $inboxPath)) {
        Write-TickLog "No inbox file found."
        exit 0
    }

    $seen = @(Get-Content -LiteralPath $seenPath | Where-Object { $_.Trim() })
    $newPackets = New-Object System.Collections.Generic.List[object]

    foreach ($line in (Get-Content -LiteralPath $inboxPath)) {
        if (-not $line.Trim()) {
            continue
        }

        $packet = $line | ConvertFrom-Json
        if ($packet.to -and ([string]$packet.to) -notmatch "Bosswoman") {
            continue
        }

        if ($seen -contains $packet.packet_id) {
            continue
        }

        $newPackets.Add($packet)
        if ($newPackets.Count -ge $MaxPackets) {
            break
        }
    }

    if ($newPackets.Count -eq 0) {
        Write-TickLog "No new Bosswoman packets."
        exit 0
    }

    foreach ($packet in $newPackets) {
        $packetId = [string]$packet.packet_id
        $safeId = ($packetId -replace "[^A-Za-z0-9_.-]", "_")
        $packetFile = Join-Path $packetDir "$safeId.json"
        $packet | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packetFile -Encoding utf8

        Add-OutboxPacket -InboxPacket $packet -Status "in_progress" -Message "Bosswoman watcher claimed packet $packetId. LaunchCodex=$LaunchCodex."
        Add-Content -LiteralPath $seenPath -Value $packetId -Encoding utf8
        Write-TickLog "Claimed packet $packetId"

        if ($LaunchCodex) {
            $runner = Join-Path $repoRoot "scripts\bosswoman-run-packet.ps1"
            $args = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $runner,
                "-PacketFile", $packetFile,
                "-BossmanRepo", $BossmanRepo
            )
            Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null
            Write-TickLog "Started hidden Codex runner for packet $packetId"
        }
    }

    git -C $repoRoot add "controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl"
    $status = git -C $repoRoot status --short -- "controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl"
    if ($status) {
        git -C $repoRoot commit -m "mailbox: bosswoman watcher claimed packet"
        git -C $repoRoot push
        Write-TickLog "Committed and pushed watcher acknowledgements."
    }
} finally {
    if ($lockStream) {
        $lockStream.Dispose()
    }
}

