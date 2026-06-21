[CmdletBinding()]
param(
    [string]$ReplyTo = "bosswoman-24x7",
    [int]$MinRestartMinutes = 45,
    [int]$NoReceiptMinutes = 90,
    [int]$StatusMinutes = 30,
    [int]$MaxStartsPerTick = 3,
    [string]$ProjectScope = "controller,Mr.SEO,ZDH Consulting,ZDH Sales"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$stateRoot = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox\babysitter"
$logDir = Join-Path $stateRoot "logs"
$runDir = Join-Path $stateRoot "runs"
$statePath = Join-Path $stateRoot "state.json"
$lockPath = Join-Path $stateRoot "babysitter.lock"
$outboxPath = Join-Path $repoRoot "controller-mailbox\outbox\bosswoman-to-ai-manager.jsonl"
$replyScript = Join-Path $repoRoot "scripts\send-bosswoman-reply.ps1"
$codexAuto = Join-Path $repoRoot "scripts\codex-auto.ps1"

New-Item -ItemType Directory -Force -Path $stateRoot, $logDir, $runDir | Out-Null
$logPath = Join-Path $logDir ("bosswoman-babysitter-{0}.log" -f (Get-Date -Format "yyyyMMdd"))

function Write-BabysitterLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
}

function Send-BabysitterReply {
    param(
        [string]$Message,
        [string]$Status = "in_progress",
        [ValidateSet("routine", "fyi", "decision", "blocker", "critical")]
        [string]$Severity = "fyi",
        [string]$IdempotencySuffix = "babysitter"
    )

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $replyScript `
        -Message $Message `
        -Status $Status `
        -Severity $Severity `
        -ProjectScope $ProjectScope `
        -ReplyTo $ReplyTo `
        -IdempotencyKey ("bosswoman-$ReplyTo-$IdempotencySuffix-$(Get-Date -Format yyyyMMddHHmmss)") `
        -Commit | Out-Null
}

function Get-ProjectSpecs {
    @(
        [pscustomobject]@{
            Slug = "mr-seo"
            Project = "Mr.SEO"
            RepoPath = "C:\Repos\Mr.SEO"
            M1 = "Run one bounded ops/control pass, classify dirty generated outputs, run python scripts/run_ops_loop.py --ci, validate generated JSON/backlog/report outputs, and push only safe generated results or clear receipts."
            Verification = "python scripts/run_ops_loop.py --ci; then validate changed JSON files load with Python json.load."
        },
        [pscustomobject]@{
            Slug = "zdh-consulting"
            Project = "ZDH Consulting"
            RepoPath = "C:\Repos\zdhconsultingsite"
            M1 = "Review the homepage like a buyer and fix the highest-impact service/proof/contact/SEO/responsive issue."
            Verification = "npm test."
        },
        [pscustomobject]@{
            Slug = "zdh-sales"
            Project = "ZDH Sales"
            RepoPath = "C:\Repos\zdhsales"
            M1 = "Rewrite the top homepage message so the buyer understands what is sold, who it is for, and what to do next."
            Verification = "Run the README static JS/JSON-LD parse command for index.html, thank-you.html, and 404.html."
        }
    )
}

function ConvertTo-DateTimeOrNull {
    param([object]$Value)
    if (-not $Value) {
        return $null
    }
    try {
        return [DateTimeOffset]::Parse([string]$Value)
    } catch {
        return $null
    }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [ordered]@{
            started_at = [DateTimeOffset]::Now.ToString("o")
            last_status_at = ""
            projects = [ordered]@{}
        }
    }

    $raw = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $projects = [ordered]@{}
    if ($raw.projects) {
        foreach ($property in $raw.projects.PSObject.Properties) {
            $projects[$property.Name] = [ordered]@{
                pid = [string]$property.Value.pid
                last_started_at = [string]$property.Value.last_started_at
                last_receipt_at = [string]$property.Value.last_receipt_at
                starts_total = [int]($property.Value.starts_total -as [int])
            }
        }
    }

    [ordered]@{
        started_at = [string]$raw.started_at
        last_status_at = [string]$raw.last_status_at
        projects = $projects
    }
}

function Save-State {
    param([object]$State)
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
}

function Get-LatestProjectReceipt {
    param([string]$Project)
    if (-not (Test-Path -LiteralPath $outboxPath)) {
        return $null
    }

    $latest = $null
    foreach ($line in (Get-Content -LiteralPath $outboxPath)) {
        if (-not $line) {
            continue
        }
        try {
            $packet = $line | ConvertFrom-Json
        } catch {
            continue
        }

        $message = [string]$packet.message
        if ($message -notmatch "(?im)^project\s*:\s*$([regex]::Escape($Project))\s*$") {
            continue
        }
        if ($message -notmatch "(?im)^repo_path\s*:") {
            continue
        }

        $created = ConvertTo-DateTimeOrNull $packet.created_at
        if ($created -and (-not $latest -or $created -gt $latest)) {
            $latest = $created
        }
    }
    return $latest
}

function New-WorkerPrompt {
    param(
        [object]$Spec,
        [string]$RunId
    )

    $gitGuardPath = Join-Path $env:USERPROFILE ".codex\scripts\git-guard.cmd"

@"
You are Bosswoman's 24x7 Project Push Worker for $($Spec.Project) on MAYHASAPC.

Mission:
$($Spec.M1)

Repo:
$($Spec.RepoPath)

Runtime:
- This is one bounded babysitter cycle under run $RunId.
- Do 20-60 minutes of real project movement, then return a receipt.
- If the safest useful improvement is smaller, bundle related verification/cleanup before returning.
- If blocked, return a concrete blocker instead of waiting silently.

Rules:
- Keep Zev's main chat clean. Report only through the Bosswoman mailbox.
- Work only in this repo path. Do not touch billing, DNS, secrets, security, database, permissions, deploy buttons, or production account settings.
- Quality bar: do not push one-minute proof-of-life changes, label-only edits, metadata-only edits, duplicate tag cleanup, or tiny cosmetic changes unless they are bundled into a meaningful M1 improvement.
- Expected depth: 20-60 minutes of real project movement. If the first safe edit is tiny, continue into the next related proof, offer, CTA, SEO, responsive, generated-data, or verification improvement before returning.
- Every pushed commit must improve the assigned M1 in a way Zev can recognize. The receipt must say why the change matters.
- Before edits, run git status and verify the remote is the expected project remote.
- Preserve dirty/untracked files unless you can prove they are generated by your task or created by you.
- Commit and push only safe verified work for this project. If unsafe dirty state blocks you, report that blocker and stop this project.
- Use $gitGuardPath before commit/push.
- Required verification: $($Spec.Verification)
- If verification fails, fix once if clear; otherwise report the failure and do not push.

Return through:
C:\Repos\codex-ai-systems\scripts\send-bosswoman-reply.ps1 -Commit

Use:
-ReplyTo "$ReplyTo" -ProjectScope "$($Spec.Project)"

Required project receipt fields:
project:
repo_path:
branch:
commit_sha:
pushed:
verification:
result:
blockers:
next_action:

Also include:
Owner Button Needed:
Commander Approval Needed:
Critical Escalation:
System Hardening Note:
"@
}

function Start-ProjectWorker {
    param(
        [object]$Spec,
        [string]$RunId
    )

    if (-not (Test-Path -LiteralPath $Spec.RepoPath)) {
        throw "Missing repo path for $($Spec.Project): $($Spec.RepoPath)"
    }

    $projectRunDir = Join-Path $runDir $RunId
    New-Item -ItemType Directory -Force -Path $projectRunDir | Out-Null
    $prompt = New-WorkerPrompt -Spec $Spec -RunId $RunId
    $promptPath = Join-Path $projectRunDir "$($Spec.Slug).prompt.txt"
    $stdoutPath = Join-Path $projectRunDir "$($Spec.Slug).stdout.log"
    $stderrPath = Join-Path $projectRunDir "$($Spec.Slug).stderr.log"
    Set-Content -LiteralPath $promptPath -Value $prompt -Encoding utf8

    $args = @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $codexAuto,
        "-ForceCodex",
        "-NoOptimizeCredits",
        "-Sandbox", "danger-full-access",
        "-ApprovalPolicy", "never",
        "-Cwd", $Spec.RepoPath,
        $prompt
    )

    Start-Process -FilePath "powershell.exe" `
        -ArgumentList $args `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
}

$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    Write-BabysitterLog "Another babysitter tick is already running; exiting."
    exit 0
}

try {
    $hostName = (hostname).Trim()
    $who = (whoami).Trim()
    if ($hostName -ine "mayhasapc" -or $who -ine "mayhasapc\meira") {
        throw "Refusing babysitter tick on wrong machine/user: host=$hostName user=$who"
    }

    $state = Read-State
    $now = [DateTimeOffset]::Now
    $runId = Get-Date -Format "yyyyMMdd-HHmmss"
    $starts = @()
    $statusLines = @()

    foreach ($spec in (Get-ProjectSpecs)) {
        if (-not $state["projects"].Contains($spec.Slug)) {
            $state["projects"][$spec.Slug] = [ordered]@{
                pid = ""
                last_started_at = ""
                last_receipt_at = ""
                starts_total = 0
            }
        }

        $projectState = $state["projects"][$spec.Slug]
        $pidText = [string]$projectState["pid"]
        $active = $false
        if ($pidText) {
            $active = [bool](Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue)
        }

        $latestReceipt = Get-LatestProjectReceipt -Project $spec.Project
        if ($latestReceipt) {
            $projectState["last_receipt_at"] = $latestReceipt.ToString("o")
        }

        $lastStarted = ConvertTo-DateTimeOrNull $projectState["last_started_at"]
        $shouldStart = $false
        $reason = ""

        if ($active) {
            $reason = "active pid=$pidText"
        } elseif (-not $lastStarted) {
            $shouldStart = $true
            $reason = "no prior worker"
        } elseif ($latestReceipt -and $latestReceipt -gt $lastStarted) {
            $shouldStart = $true
            $reason = "last worker returned receipt"
        } else {
            $ageMinutes = ($now - $lastStarted).TotalMinutes
            if ($ageMinutes -ge $NoReceiptMinutes) {
                $shouldStart = $true
                $reason = "stale/no receipt for $([math]::Round($ageMinutes, 1))m"
            } elseif ($ageMinutes -lt $MinRestartMinutes) {
                $reason = "cooldown $([math]::Round($ageMinutes, 1))m"
            } else {
                $reason = "waiting for receipt $([math]::Round($ageMinutes, 1))m"
            }
        }

        if ($shouldStart -and $starts.Count -lt $MaxStartsPerTick) {
            $process = Start-ProjectWorker -Spec $spec -RunId $runId
            $projectState["pid"] = [string]$process.Id
            $projectState["last_started_at"] = $now.ToString("o")
            $projectState["starts_total"] = [int]$projectState["starts_total"] + 1
            $starts += "$($spec.Project): started pid=$($process.Id); reason=$reason"
            $statusLines += "$($spec.Project): started pid=$($process.Id)"
        } else {
            $statusLines += "$($spec.Project): $reason"
        }
    }

    $sendStatus = $false
    $lastStatus = ConvertTo-DateTimeOrNull $state["last_status_at"]
    if ($starts.Count -gt 0 -or -not $lastStatus -or ($now - $lastStatus).TotalMinutes -ge $StatusMinutes) {
        $sendStatus = $true
        $state["last_status_at"] = $now.ToString("o")
    }

    Save-State -State $state
    Write-BabysitterLog "Tick complete. starts=$($starts.Count). $($statusLines -join ' | ')"

    if ($sendStatus) {
        $actionsText = if ($starts.Count -gt 0) { $starts -join "`n" } else { "No new workers needed this tick." }
        $message = @"
Agent: Bosswoman MAYHASAPC 24x7 babysitter
Status: in_progress
Runtime State: 24x7 babysitter tick complete; starts_this_tick=$($starts.Count); max_starts_per_tick=$MaxStartsPerTick; min_restart_minutes=$MinRestartMinutes; no_receipt_minutes=$NoReceiptMinutes.
Projects:
$($statusLines -join "`n")
Actions Taken:
$actionsText
Verification: Host/user verified as $hostName/$who; state saved at $statePath; workers launched hidden through codex-auto when needed.
Result: Babysitter remains active and will keep checking these projects through the scheduled task.
Blockers: None at babysitter level.
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: Continue recurring ticks; project workers return commit/verification receipts through mailbox only.
System Hardening Note: This is a recurring project babysitter, not broad Bossman dispatch and not send_message_to_thread.
"@
        Send-BabysitterReply -Message $message -Status "in_progress" -Severity "fyi" -IdempotencySuffix "tick"
    }
} catch {
    Write-BabysitterLog "Tick failed: $($_.Exception.Message)"
    try {
        Send-BabysitterReply -Status "blocked" -Severity "blocker" -IdempotencySuffix "failed" -Message @"
Agent: Bosswoman MAYHASAPC 24x7 babysitter
Status: blocked
Runtime State: Babysitter tick failed before safe completion.
Result: $($_.Exception.Message)
Blockers: Babysitter tick failure.
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should inspect $logPath and repair the babysitter script/task before increasing project fanout.
System Hardening Note: The babysitter failed closed and reported the error through mailbox.
"@
    } catch {
        Write-BabysitterLog "Failed to send failure reply: $($_.Exception.Message)"
    }
} finally {
    if ($lockStream) {
        $lockStream.Dispose()
    }
}
