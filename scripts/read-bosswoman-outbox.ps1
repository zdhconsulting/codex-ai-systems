[CmdletBinding()]
param(
    [int]$Tail = 20,
    [switch]$Landed,
    [int]$SinceHours = 24,
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

if ($Landed) {
    $cutoff = [DateTimeOffset]::Now.AddHours(-1 * [math]::Abs($SinceHours))
    $landedPackets = @()

    foreach ($packet in ($packets | Sort-Object created_at)) {
        if ($packet.PSObject.Properties.Name -contains "parse_error") {
            continue
        }

        $created = $null
        try {
            $created = [DateTimeOffset]::Parse([string]$packet.created_at)
        } catch {
            continue
        }

        if ($created -lt $cutoff) {
            continue
        }

        $message = [string]$packet.message
        if ($message -notmatch "(?im)^pushed\s*:\s*(yes|true)\b") {
            continue
        }

        $project = ""
        $repoPath = ""
        $branch = ""
        $commitSha = ""
        $result = ""

        if ($message -match "(?im)^project\s*:\s*(.+)$") {
            $project = $Matches[1].Trim()
        }
        if ($message -match "(?im)^repo_path\s*:\s*(.+)$") {
            $repoPath = $Matches[1].Trim()
        }
        if ($message -match "(?im)^branch\s*:\s*(.+)$") {
            $branch = $Matches[1].Trim()
        }
        if ($message -match "(?im)^commit_sha\s*:\s*(.+)$") {
            $commitSha = ($Matches[1].Trim() -split "\s+")[0]
        }
        if ($message -match "(?ims)^result\s*:\s*(.+?)(?:\r?\nblockers\s*:|\r?\nnext_action\s*:|\z)") {
            $result = (($Matches[1].Trim() -replace "\s+", " ") -replace "\|", "/")
            if ($result.Length -gt 180) {
                $result = $result.Substring(0, 177) + "..."
            }
        }

        $landedPackets += [pscustomobject]@{
            created_at = $created.ToString("yyyy-MM-dd HH:mm:ss zzz")
            project = if ($project) { $project } else { [string]$packet.project_scope }
            repo_path = $repoPath
            branch = $branch
            commit_sha = $commitSha
            result = $result
            packet_id = [string]$packet.packet_id
        }
    }

    if (-not $landedPackets) {
        Write-Output "No Bosswoman pushed receipts found in the last $SinceHours hour(s)."
        exit 0
    }

    Write-Output "Bosswoman pushed receipts in the last $SinceHours hour(s):"
    foreach ($item in $landedPackets) {
        Write-Output ("- {0} | {1} | {2} | {3} | {4}" -f $item.created_at, $item.project, $item.branch, $item.commit_sha, $item.result)
    }
    exit 0
}

$packets |
    Sort-Object created_at |
    Select-Object -Last $Tail |
    ConvertTo-Json -Depth 10
