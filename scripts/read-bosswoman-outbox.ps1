[CmdletBinding()]
param(
    [int]$Tail = 20,
    [switch]$Pull
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$outboxPath = Join-Path $repoRoot "controller-mailbox\outbox\bosswoman-to-ai-manager.jsonl"

if ($Pull) {
    git -C $repoRoot pull --ff-only
}

if (-not (Test-Path -LiteralPath $outboxPath)) {
    Write-Output "No Bosswoman outbox packets found."
    exit 0
}

$packets = foreach ($line in (Get-Content -LiteralPath $outboxPath)) {
    if (-not $line.Trim()) {
        continue
    }

    try {
        $line | ConvertFrom-Json
    } catch {
        [pscustomobject]@{
            parse_error = $_.Exception.Message
            raw = $line
        }
    }
}

if (-not $packets) {
    Write-Output "No Bosswoman outbox packets found."
    exit 0
}

$packets |
    Sort-Object created_at |
    Select-Object -Last $Tail |
    ConvertTo-Json -Depth 10

