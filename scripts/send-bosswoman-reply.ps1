[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [ValidateSet("routine", "fyi", "decision", "blocker", "critical")]
    [string]$Severity = "fyi",

    [ValidateSet("new", "in_progress", "done", "blocked", "superseded")]
    [string]$Status = "done",

    [string]$Type = "return_packet",
    [string]$ProjectScope = "controller",
    [string]$From = "Bosswoman MAYHASAPC",
    [string]$To = "AI Manager",
    [string]$ReplyTo = "",
    [string]$IdempotencyKey = "",
    [switch]$Commit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$outboxDir = Join-Path $repoRoot "controller-mailbox\outbox"
$outboxPath = Join-Path $outboxDir "bosswoman-to-ai-manager.jsonl"

New-Item -ItemType Directory -Force -Path $outboxDir | Out-Null

if ($Commit) {
    git -C $repoRoot pull --ff-only
}

$timestamp = [DateTimeOffset]::UtcNow
$packetId = "bosswoman-{0}-{1}" -f $timestamp.ToUnixTimeMilliseconds(), ([Guid]::NewGuid().ToString("N").Substring(0, 8))

$scopeValue = if ($ProjectScope -match ",") {
    @($ProjectScope.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    $ProjectScope
}

$packet = [ordered]@{
    packet_id = $packetId
    created_at = $timestamp.ToString("o")
    from = $From
    to = $To
    type = $Type
    severity = $Severity
    project_scope = $scopeValue
    requested_action = "ai_manager_review"
    status = $Status
    message = $Message
}

if ($ReplyTo) {
    $packet.reply_to = $ReplyTo
}

if ($IdempotencyKey) {
    $packet.idempotency_key = $IdempotencyKey
}

$json = $packet | ConvertTo-Json -Depth 8 -Compress
Add-Content -LiteralPath $outboxPath -Value $json -Encoding utf8

if ($Commit) {
    git -C $repoRoot add "controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl"
    git -C $repoRoot commit -m "mailbox: send bosswoman reply $packetId"
    git -C $repoRoot push
}

$packet | ConvertTo-Json -Depth 8

