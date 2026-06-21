[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PacketFile,

    [string]$RepoRoot = "",
    [string]$BossmanRepo = "C:\Repos\bossman"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$WorkingDirectory = $PWD.Path
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

function Get-GitText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkDir,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $WorkDir)) {
        return "MISSING_PATH"
    }

    $result = Invoke-NativeCommand -FilePath "git" -Arguments (@("-C", $WorkDir) + $Arguments) -WorkingDirectory $WorkDir
    if ($result.ExitCode -ne 0) {
        return "GIT_FAILED($($result.ExitCode)): $($result.Output)"
    }
    return $result.Output
}

function Get-RepoSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedRemote
    )

    $exists = Test-Path -LiteralPath $Path
    if (-not $exists) {
        return [pscustomobject]@{
            Name = $Name
            Path = $Path
            Exists = $false
            Branch = "missing"
            ExpectedRemotePresent = $false
            DirtyCount = -1
            DirtyPreview = "missing repo path"
        }
    }

    $branch = Get-GitText -WorkDir $Path -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
    $remotes = Get-GitText -WorkDir $Path -Arguments @("remote", "-v")
    $status = Get-GitText -WorkDir $Path -Arguments @("status", "--short")
    $dirtyLines = @()
    if ($status -and $status -ne "") {
        $dirtyLines = @($status -split "`r?`n" | Where-Object { $_.Trim() })
    }

    [pscustomobject]@{
        Name = $Name
        Path = $Path
        Exists = $true
        Branch = $branch
        ExpectedRemotePresent = ($remotes -like "*$ExpectedRemote*")
        DirtyCount = $dirtyLines.Count
        DirtyPreview = (($dirtyLines | Select-Object -First 12) -join "; ")
    }
}

function Send-BosswomanReply {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Packet,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Status = "done",
        [string]$Severity = "fyi",
        [string]$ProjectScope = "controller",
        [string]$IdempotencySuffix = "native"
    )

    $replyScript = Join-Path $RepoRoot "scripts\send-bosswoman-reply.ps1"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $replyScript `
        -Message $Message `
        -Status $Status `
        -Severity $Severity `
        -ProjectScope $ProjectScope `
        -ReplyTo ([string]$Packet.packet_id) `
        -IdempotencyKey ("bosswoman-$($Packet.packet_id)-$IdempotencySuffix") | Out-Null
}

function Get-RunnerProcessSummary {
    try {
        $matches = @(Get-CimInstance Win32_Process | Where-Object {
            $_.CommandLine -and ($_.CommandLine -match "bosswoman-run-packet|bosswoman-native-action|codex-auto|Bosswoman mailbox packet")
        } | Select-Object -First 20 ProcessId, Name, CommandLine)

        if ($matches.Count -eq 0) {
            return "0 matching bosswoman/codex runner processes"
        }

        return (($matches | ForEach-Object {
            "pid=$($_.ProcessId) name=$($_.Name) cmd=$($_.CommandLine)"
        }) -join "`n")
    } catch {
        return "runner process inspection failed: $($_.Exception.Message)"
    }
}

function Invoke-ReadinessProbe {
    param([object]$Packet)

    $hostName = (hostname).Trim()
    $who = (whoami).Trim()

    $codexSystemsPull = Invoke-NativeCommand -FilePath "git" -Arguments @("-C", $RepoRoot, "pull", "--ff-only") -WorkingDirectory $RepoRoot
    $bossmanPull = Invoke-NativeCommand -FilePath "git" -Arguments @("-C", $BossmanRepo, "pull", "--ff-only") -WorkingDirectory $BossmanRepo

    $requiredFiles = @(
        (Join-Path $RepoRoot "scripts\bosswoman-mailbox-tick.ps1"),
        (Join-Path $RepoRoot "scripts\bosswoman-run-packet.ps1"),
        (Join-Path $RepoRoot "scripts\bosswoman-native-action.ps1"),
        (Join-Path $BossmanRepo "BOSSWOMAN_CONTROLLER.md"),
        (Join-Path $BossmanRepo "data\controller-profiles\bosswoman.mayhasapc.json")
    )
    $missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) })

    $taskInfo = "unknown"
    try {
        $task = Get-ScheduledTask -TaskName "ZDH Bosswoman Mailbox Watcher" -ErrorAction Stop
        $taskInfo = "State=$($task.State); TaskPath=$($task.TaskPath)"
    } catch {
        $taskInfo = "missing_or_unreadable: $($_.Exception.Message)"
    }

    $repos = @()
    $repos += Get-RepoSummary -Name "Mr.SEO" -Path "C:\Repos\Mr.SEO" -ExpectedRemote "https://github.com/zdhconsulting/Mr.SEO.git"
    $repos += Get-RepoSummary -Name "ZDH Consulting" -Path "C:\Repos\zdhconsultingsite" -ExpectedRemote "https://github.com/zdhconsulting/zdhconsultingsite.git"
    $repos += Get-RepoSummary -Name "ZDH Sales" -Path "C:\Repos\zdhsales" -ExpectedRemote "https://github.com/zdhconsulting/zdhsales.git"

    $repoText = (($repos | ForEach-Object {
        "$($_.Name): path=$($_.Path); exists=$($_.Exists); branch=$($_.Branch); expected_remote=$($_.ExpectedRemotePresent); dirty_count=$($_.DirtyCount); dirty_preview=$($_.DirtyPreview)"
    }) -join "`n")

    $ready = (
        $hostName -ieq "mayhasapc" -and
        $who -ieq "mayhasapc\meira" -and
        $missingFiles.Count -eq 0 -and
        @($repos | Where-Object { -not $_.Exists -or -not $_.ExpectedRemotePresent }).Count -eq 0
    )

    $message = @"
Agent: Bosswoman MAYHASAPC native readiness
Status: $(if ($ready) { "ready" } else { "blocked" })
Machine: $hostName
User: $who
Watcher State: $taskInfo
Repos Verified:
$repoText
Dirty State Summary: Dirty files exist and must be classified before commits. Mr.SEO generated-output dirt is expected; ZDH Consulting/ZDH Sales untracked files must be preserved unless the worker proves ownership.
Native Pull Results: codex-ai-systems=$($codexSystemsPull.ExitCode) $($codexSystemsPull.Output); bossman=$($bossmanPull.ExitCode) $($bossmanPull.Output)
Runner Processes: $(Get-RunnerProcessSummary)
Ready For Overnight Enable: $(if ($ready) { "yes" } else { "no" })
Blockers: $(if ($missingFiles.Count -gt 0) { "Missing files: $($missingFiles -join ", ")" } elseif (-not $ready) { "machine/user/repo verification failed" } else { "None" })
Owner Button Needed: None.
Commander Approval Needed: None for readiness. Overnight command packet is the explicit enable.
Critical Escalation: None.
Next Best Action: $(if ($ready) { "AI Manager may send run_bosswoman_overnight_controlled_6h." } else { "Fix the readiness blocker before enabling overnight work." })
System Hardening Note: Readiness is now handled natively by the mailbox watcher, so a silent Codex runner cannot block the readiness gate.
"@

    Send-BosswomanReply -Packet $Packet -Message $message -Status $(if ($ready) { "done" } else { "blocked" }) -Severity $(if ($ready) { "fyi" } else { "blocker" }) -ProjectScope "controller,Mr.SEO,ZDH Consulting,ZDH Sales" -IdempotencySuffix "native-readiness"
}

function New-WorkerPrompt {
    param(
        [string]$Project,
        [string]$RepoPath,
        [string]$M1,
        [string]$Verification
    )

@"
You are Bosswoman's overnight Project Push Worker for $Project on MAYHASAPC.

Mission:
$M1

Repo:
$RepoPath

Rules:
- Keep Zev's main chat clean. Report only through the Bosswoman mailbox.
- Work only in this repo path. Do not touch billing, DNS, secrets, security, database, permissions, deploy buttons, or production account settings.
- Before edits, run git status and verify the remote is the expected project remote.
- Preserve dirty/untracked files unless you can prove they are generated by your task or created by you.
- Commit and push only safe verified work for this project. If unsafe dirty state blocks you, report that blocker and stop this project.
- Use C:\Users\zev\.codex\scripts\git-guard.cmd before commit/push.
- Required verification: $Verification
- If verification fails, fix once if clear; otherwise report the failure and do not push.

Return through:
C:\Repos\codex-ai-systems\scripts\send-bosswoman-reply.ps1 -Commit

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

function Start-CodexWorker {
    param(
        [string]$RunDir,
        [string]$Slug,
        [string]$Project,
        [string]$RepoPath,
        [string]$Prompt
    )

    if (-not (Test-Path -LiteralPath $RepoPath)) {
        return [pscustomobject]@{
            Project = $Project
            Started = $false
            Pid = ""
            Reason = "Missing repo path $RepoPath"
        }
    }

    $codexAuto = Join-Path $RepoRoot "scripts\codex-auto.ps1"
    $promptPath = Join-Path $RunDir "$Slug.prompt.txt"
    $stdoutPath = Join-Path $RunDir "$Slug.stdout.log"
    $stderrPath = Join-Path $RunDir "$Slug.stderr.log"
    Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding utf8

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $codexAuto,
        "-ForceCodex",
        "-NoOptimizeCredits",
        "-Cwd", $RepoPath,
        $Prompt
    )

    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $args `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    [pscustomobject]@{
        Project = $Project
        Started = $true
        Pid = $process.Id
        Reason = "started hidden worker; prompt=$promptPath; stdout=$stdoutPath; stderr=$stderrPath"
    }
}

function Invoke-OvernightRun {
    param([object]$Packet)

    $hostName = (hostname).Trim()
    $who = (whoami).Trim()
    if ($hostName -ine "mayhasapc" -or $who -ine "mayhasapc\meira") {
        throw "Refusing overnight run on wrong machine/user: host=$hostName user=$who"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $runDir = Join-Path $env:LOCALAPPDATA "ZDH\BosswomanMailbox\overnight\$timestamp"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    $workers = @()
    $workers += Start-CodexWorker -RunDir $runDir -Slug "mr-seo" -Project "Mr.SEO" -RepoPath "C:\Repos\Mr.SEO" -Prompt (New-WorkerPrompt -Project "Mr.SEO" -RepoPath "C:\Repos\Mr.SEO" -M1 "Run one bounded ops/control pass, classify dirty generated outputs, run python scripts/run_ops_loop.py --ci, validate generated JSON/backlog/report outputs, and push only safe generated results or clear receipts." -Verification "python scripts/run_ops_loop.py --ci; then validate changed JSON files load with Python json.load.")
    $workers += Start-CodexWorker -RunDir $runDir -Slug "zdh-consulting" -Project "ZDH Consulting" -RepoPath "C:\Repos\zdhconsultingsite" -Prompt (New-WorkerPrompt -Project "ZDH Consulting" -RepoPath "C:\Repos\zdhconsultingsite" -M1 "Review the homepage like a buyer and fix the highest-impact service/proof/contact/SEO/responsive issue." -Verification "npm test.")
    $workers += Start-CodexWorker -RunDir $runDir -Slug "zdh-sales" -Project "ZDH Sales" -RepoPath "C:\Repos\zdhsales" -Prompt (New-WorkerPrompt -Project "ZDH Sales" -RepoPath "C:\Repos\zdhsales" -M1 "Rewrite the top homepage message so the buyer understands what is sold, who it is for, and what to do next." -Verification "Run the README static JS/JSON-LD parse command for index.html, thank-you.html, and 404.html.")

    $workerText = (($workers | ForEach-Object {
        "$($_.Project): started=$($_.Started); pid=$($_.Pid); $($_.Reason)"
    }) -join "`n")

    $message = @"
Agent: Bosswoman MAYHASAPC native overnight launcher
Status: night_run_started
Machine: $hostName
User: $who
Runtime State: Started controlled 6+ hour overnight run with max 3 initial hidden project workers and no broad Bossman dispatch.
Projects Checked:
$workerText
Repos Verified: Project workers are required to verify path/remotes before edits and before commit/push.
Actions Taken: Created run directory $runDir and launched one hidden worker per project.
Verification: Native launcher verified machine/user and process start. Each project worker owns project-level verification.
Result: Overnight work started.
Blockers: $(if (@($workers | Where-Object { -not $_.Started }).Count -gt 0) { "One or more workers failed to start; see Projects Checked." } else { "None at launcher level." })
Owner Button Needed: None.
Commander Approval Needed: None. This packet is the explicit overnight enable.
Critical Escalation: None.
Next Best Action: Wait for project receipt packets. If no project lands progress within 90 minutes, classify as no_delivery_progress.
System Hardening Note: Launcher uses native mailbox control for start/status and hidden project workers only; it does not use send_message_to_thread, WinRM, deploys, or broad Bossman dispatch.
"@

    Send-BosswomanReply -Packet $Packet -Message $message -Status "in_progress" -Severity "fyi" -ProjectScope "controller,Mr.SEO,ZDH Consulting,ZDH Sales" -IdempotencySuffix "native-overnight-start"
}

$packet = Get-Content -Raw -LiteralPath $PacketFile | ConvertFrom-Json
$requestedAction = [string]$packet.requested_action

try {
    switch ($requestedAction) {
        "bosswoman_readiness_probe_for_overnight_run" {
            Invoke-ReadinessProbe -Packet $packet
            exit 0
        }
        "run_bosswoman_overnight_controlled_6h" {
            Invoke-OvernightRun -Packet $packet
            exit 0
        }
        default {
            exit 2
        }
    }
} catch {
    $message = @"
Agent: Bosswoman MAYHASAPC native action
Status: blocked
Machine: $((hostname).Trim())
User: $((whoami).Trim())
Requested Action: $requestedAction
Result: Native action failed before safe completion.
Blockers: $($_.Exception.Message)
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should repair the native action or send a narrower packet.
System Hardening Note: Native action failed closed before worker fanout.
"@
    Send-BosswomanReply -Packet $packet -Message $message -Status "blocked" -Severity "blocker" -ProjectScope "controller,Mr.SEO,ZDH Consulting,ZDH Sales" -IdempotencySuffix "native-failed"
    exit 0
}
