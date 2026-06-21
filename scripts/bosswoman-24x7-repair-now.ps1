[CmdletBinding()]
param(
    [string]$PacketId = "ai-manager-1782022886886-29880f2a",
    [string]$BossmanRepo = "C:\Repos\bossman",
    [string]$RequiredHost = "mayhasapc",
    [switch]$AllowAnyHost
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$inboxPath = Join-Path $repoRoot "controller-mailbox\inbox\ai-manager-to-bosswoman.jsonl"
$outboxPath = Join-Path $repoRoot "controller-mailbox\outbox\bosswoman-to-ai-manager.jsonl"
$stateDir = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox"
$packetDir = Join-Path $stateDir "packets"
$logDir = Join-Path $stateDir "logs"
$lockPath = Join-Path $stateDir "watcher.lock"

New-Item -ItemType Directory -Force -Path $stateDir, $packetDir, $logDir | Out-Null

function Write-RepairLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $path = Join-Path $logDir ("bosswoman-24x7-repair-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
    "[$stamp] $Message" | Add-Content -LiteralPath $path -Encoding utf8
}

function Get-TaskSummary {
    $names = @("ZDH Bosswoman 24x7 Babysitter", "ZDH Bosswoman Mailbox Watcher")
    $summaries = foreach ($name in $names) {
        try {
            $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
            $last = if ($info) { $info.LastTaskResult } else { "unknown" }
            "$name state=$($task.State) last_result=$last"
        } catch {
            "$name missing_or_unreadable=$($_.Exception.Message)"
        }
    }
    return ($summaries -join "`n")
}

function Test-WatcherLock {
    if (-not (Test-Path -LiteralPath $lockPath)) {
        return "available; lock file absent"
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        return "available; lock opened"
    } catch {
        return "busy_or_stuck; $($_.Exception.Message)"
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Find-InboxPacket {
    param([string]$Id)

    if (-not (Test-Path -LiteralPath $inboxPath)) {
        throw "Inbox file not found: $inboxPath"
    }

    foreach ($line in (Get-Content -LiteralPath $inboxPath)) {
        if (-not $line.Trim()) {
            continue
        }

        $packet = $line | ConvertFrom-Json
        if ([string]$packet.packet_id -eq $Id) {
            return $packet
        }
    }

    throw "Packet not found in inbox: $Id"
}

function Publish-RepairReceipt {
    param(
        [string]$Status,
        [string]$Severity,
        [string]$Message
    )

    $timestamp = [DateTimeOffset]::UtcNow
    $packet = [ordered]@{
        packet_id = "bosswoman-repair-{0}-{1}" -f $timestamp.ToUnixTimeMilliseconds(), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
        created_at = $timestamp.ToString("o")
        from = "Bosswoman MAYHASAPC repair"
        to = "AI Manager"
        type = "return_packet"
        severity = $Severity
        project_scope = @("controller", "Mr.SEO", "ZDH Consulting", "ZDH Sales")
        requested_action = "ai_manager_review"
        status = $Status
        message = $Message
        reply_to = $PacketId
        idempotency_key = "bosswoman-$PacketId-24x7-repair-now-$($timestamp.ToUnixTimeMilliseconds())"
    }

    $json = $packet | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $outboxPath -Value $json -Encoding utf8

    git -C $repoRoot add "controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl"
    $dirty = git -C $repoRoot status --short -- "controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl"
    if ($dirty) {
        git -C $repoRoot commit -m "mailbox: bosswoman 24x7 repair receipt"
        git -C $repoRoot push
    } else {
        git -C $repoRoot push
    }
}

$hostName = (hostname).Trim()
$who = (whoami).Trim()
Write-RepairLog "Repair start PacketId=$PacketId host=$hostName user=$who"

if ((-not $AllowAnyHost) -and $RequiredHost -and ($hostName.ToLowerInvariant() -ne $RequiredHost.ToLowerInvariant())) {
    Write-Host "BOSSWOMAN_24X7_REPAIR_SKIP host_mismatch expected=$RequiredHost actual=$hostName"
    exit 0
}

$nativeOutput = ""
$nativeExit = 0
$status = "done"
$severity = "fyi"

try {
    git -C $repoRoot pull --ff-only | Out-Null

    $packet = Find-InboxPacket -Id $PacketId
    $packetFile = Join-Path $packetDir (($PacketId -replace "[^A-Za-z0-9_.-]", "_") + ".json")
    $packet | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $packetFile -Encoding utf8

    $lockSummary = Test-WatcherLock
    $nativeAction = Join-Path $repoRoot "scripts\bosswoman-native-action.ps1"
    if (-not (Test-Path -LiteralPath $nativeAction)) {
        throw "Missing native action script: $nativeAction"
    }

    $nativeOutput = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $nativeAction -PacketFile $packetFile -RepoRoot $repoRoot -BossmanRepo $BossmanRepo 2>&1 | Out-String).Trim()
    $nativeExit = $LASTEXITCODE
    if ($nativeExit -ne 0) {
        $status = "blocked"
        $severity = "blocker"
    }
} catch {
    $status = "blocked"
    $severity = "blocker"
    $nativeOutput = $_.Exception.Message
    $nativeExit = 1
}

$taskSummary = Get-TaskSummary
$lockSummary = Test-WatcherLock
$lastOutbox = if (Test-Path -LiteralPath $outboxPath) {
    ((Get-Content -LiteralPath $outboxPath -Tail 3) -join "`n")
} else {
    "No outbox file"
}

$message = @"
Agent: Bosswoman MAYHASAPC 24x7 repair now
Status: $status
Machine: $hostName
User: $who
Packet: $PacketId
Native Exit: $nativeExit
Watcher Lock: $lockSummary
Task Summary:
$taskSummary
Native Output:
$nativeOutput
Recent Local Outbox:
$lastOutbox
Result: Direct native 24x7 repair path ran and this receipt was pushed from MAYHASAPC.
Blockers: $(if ($status -eq "done") { "None at repair level." } else { "Native action or local repair failed; see Native Output." })
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should pull the mailbox and verify the 24x7 babysitter emits project receipts.
System Hardening Note: This bypasses the watcher claim path and directly publishes a mailbox receipt so local silent failures do not hide from AI Manager.
"@

Publish-RepairReceipt -Status $status -Severity $severity -Message $message
Write-Host "BOSSWOMAN_24X7_REPAIR_PUBLISHED status=$status native_exit=$nativeExit"
if ($nativeOutput) {
    Write-Host "BOSSWOMAN_24X7_NATIVE_OUTPUT_BEGIN"
    Write-Host $nativeOutput
    Write-Host "BOSSWOMAN_24X7_NATIVE_OUTPUT_END"
}
