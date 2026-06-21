[CmdletBinding()]
param(
    [int]$PollSeconds = 30,
    [switch]$Once,
    [switch]$NoMarkSeen
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$inboxPath = Join-Path $repoRoot "controller-mailbox\inbox\ai-manager-to-bosswoman.jsonl"
$stateDir = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox"
$seenPath = Join-Path $stateDir "seen-ai-manager-packets.txt"

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
if (-not (Test-Path -LiteralPath $seenPath)) {
    New-Item -ItemType File -Force -Path $seenPath | Out-Null
}

do {
    git -C $repoRoot pull --ff-only | Out-Null

    if (-not (Test-Path -LiteralPath $inboxPath)) {
        if ($Once) {
            Write-Output "No AI Manager inbox packets found."
        }
    } else {
        $seen = @(Get-Content -LiteralPath $seenPath | Where-Object { $_.Trim() })
        $newPackets = @()

        foreach ($line in (Get-Content -LiteralPath $inboxPath)) {
            if (-not $line.Trim()) {
                continue
            }

            try {
                $packet = $line | ConvertFrom-Json
                if ($seen -notcontains $packet.packet_id) {
                    $newPackets += $packet
                }
            } catch {
                $newPackets += [pscustomobject]@{
                    packet_id = "parse-error"
                    parse_error = $_.Exception.Message
                    raw = $line
                }
            }
        }

        if ($newPackets.Count -gt 0) {
            $newPackets | ConvertTo-Json -Depth 10

            if (-not $NoMarkSeen) {
                foreach ($packet in $newPackets) {
                    if ($packet.packet_id -and $packet.packet_id -ne "parse-error") {
                        Add-Content -LiteralPath $seenPath -Value $packet.packet_id -Encoding utf8
                    }
                }
            }
        } elseif ($Once) {
            Write-Output "No new AI Manager inbox packets."
        }
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds $PollSeconds
} while ($true)

