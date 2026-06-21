[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PacketFile,

    [string]$BossmanRepo = "C:\Repos\bossman"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$logPath = Join-Path $logDir ("bosswoman-run-packet-{0}.log" -f (Get-Date -Format "yyyyMMdd"))

function Write-RunLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
}

$packet = Get-Content -Raw -LiteralPath $PacketFile | ConvertFrom-Json
$packetId = [string]$packet.packet_id
if (-not $packetId) {
    throw "Packet file has no packet_id: $PacketFile"
}

$prompt = @"
Bosswoman mailbox packet: $packetId

You are Bosswoman, the standalone Bossman controller on MAYHASAPC.

Read the durable controller contracts before acting:
- C:\Repos\codex-ai-systems\controller-mailbox\bosswoman-controller.json
- C:\Repos\codex-ai-systems\controller-mailbox\README.md
- C:\Repos\bossman\BOSSWOMAN_CONTROLLER.md
- C:\Repos\bossman\data\controller-profiles\bosswoman.mayhasapc.json

Packet:
$($packet | ConvertTo-Json -Depth 12)

Rules:
- Keep Zev's main chat clean.
- Do not enable always-on dispatch unless this packet explicitly says to enable it.
- Do not launch broad worker fanout.
- Do not deploy or touch billing, DNS, secrets, security, database, permissions, or production account settings.
- Verify exact repo paths and remotes before project work.
- Use the mailbox for the return packet:
  C:\Repos\codex-ai-systems\scripts\send-bosswoman-reply.ps1
- Include packet_id $packetId in reply_to.

Return through mailbox with:
Agent:
Status:
Machine:
Projects Checked:
Repos Verified:
Runtime State:
Actions Taken:
Verification:
Result:
Blockers:
Owner Button Needed:
Commander Approval Needed:
Critical Escalation:
Next Best Action:
System Hardening Note:
"@

Write-RunLog "Starting Codex for packet $packetId using Bossman repo $BossmanRepo"

$codexAuto = Join-Path $repoRoot "scripts\codex-auto.ps1"
if (-not (Test-Path -LiteralPath $codexAuto)) {
    throw "codex-auto.ps1 not found at $codexAuto"
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $codexAuto -ForceCodex -NoOptimizeCredits -Cwd $BossmanRepo $prompt *>> $logPath
$exitCode = $LASTEXITCODE
Write-RunLog "Codex finished for packet $packetId with exit code $exitCode"
exit $exitCode

