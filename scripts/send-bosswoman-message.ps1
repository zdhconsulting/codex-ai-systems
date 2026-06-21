[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [ValidateSet("routine", "fyi", "decision", "blocker", "critical")]
    [string]$Severity = "decision",

    [string]$Type = "command",
    [string]$ProjectScope = "controller",
    [string]$RequestedAction = "reply_with_return_packet",
    [string]$From = "AI Manager",
    [string]$To = "Bosswoman MAYHASAPC",
    [string]$ReplyTo = "",
    [string]$IdempotencyKey = "",
    [switch]$Commit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$inboxDir = Join-Path $repoRoot "controller-mailbox\inbox"
$inboxPath = Join-Path $inboxDir "ai-manager-to-bosswoman.jsonl"

New-Item -ItemType Directory -Force -Path $inboxDir | Out-Null

if ($Commit) {
    git -C $repoRoot pull --ff-only
}

$timestamp = [DateTimeOffset]::UtcNow
$packetId = "ai-manager-{0}-{1}" -f $timestamp.ToUnixTimeMilliseconds(), ([Guid]::NewGuid().ToString("N").Substring(0, 8))

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
    requested_action = $RequestedAction
    status = "new"
    message = $Message
}

if ($ReplyTo) {
    $packet.reply_to = $ReplyTo
}

if ($IdempotencyKey) {
    $packet.idempotency_key = $IdempotencyKey
}

$json = $packet | ConvertTo-Json -Depth 8 -Compress
Add-Content -LiteralPath $inboxPath -Value $json -Encoding utf8

if ($Commit) {
    git -C $repoRoot add "controller-mailbox/inbox/ai-manager-to-bosswoman.jsonl"
    git -C $repoRoot commit -m "mailbox: send bosswoman packet $packetId"
    git -C $repoRoot push
}

$packet | ConvertTo-Json -Depth 8

