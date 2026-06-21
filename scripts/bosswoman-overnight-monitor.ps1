[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir,

    [Parameter(Mandatory = $true)]
    [string]$ReplyTo,

    [int]$DurationHours = 6,
    [int]$StatusMinutes = 30,
    [int]$NoProgressMinutes = 90,
    [string]$ProjectScope = "controller,Mr.SEO,ZDH Consulting,ZDH Sales"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$replyScript = Join-Path $repoRoot "scripts\send-bosswoman-reply.ps1"
$outboxPath = Join-Path $repoRoot "controller-mailbox\outbox\bosswoman-to-ai-manager.jsonl"
$logPath = Join-Path $RunDir "overnight-monitor.log"
$statePath = Join-Path $RunDir "run-state.json"

function Write-MonitorLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
}

function Send-MonitorReply {
    param(
        [string]$Message,
        [string]$Status = "in_progress",
        [string]$Severity = "fyi",
        [string]$IdempotencySuffix = "monitor"
    )

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $replyScript `
        -Message $Message `
        -Status $Status `
        -Severity $Severity `
        -ProjectScope $ProjectScope `
        -ReplyTo $ReplyTo `
        -IdempotencyKey ("bosswoman-$ReplyTo-$IdempotencySuffix-$(Get-Date -Format yyyyMMddHHmmss)") `
        -Commit | Out-Null
}

function Get-ReceiptCount {
    if (-not (Test-Path -LiteralPath $outboxPath)) {
        return 0
    }

    $lines = @(Get-Content -LiteralPath $outboxPath | Where-Object {
        $_ -and $_ -match [regex]::Escape($ReplyTo) -and $_ -match "project|Project|Mr\.SEO|ZDH Consulting|ZDH Sales"
    })
    return $lines.Count
}

function Get-WorkerSummary {
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $summaries = @()
    foreach ($worker in @($state.workers)) {
        $pidText = [string]$worker.Pid
        $active = $false
        if ($worker.Started -and $pidText) {
            $active = [bool](Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue)
        }
        $summaries += "$($worker.Project): started=$($worker.Started); active=$active; pid=$pidText; reason=$($worker.Reason)"
    }
    return ($summaries -join "`n")
}

try {
    $started = Get-Date
    $deadline = $started.AddHours($DurationHours)
    $lastStatus = $started.AddMinutes(-1 * $StatusMinutes)
    $noProgressSent = $false

    Write-MonitorLog "Monitor started. ReplyTo=$ReplyTo RunDir=$RunDir DurationHours=$DurationHours"

    Send-MonitorReply -Status "in_progress" -Severity "fyi" -IdempotencySuffix "monitor-started" -Message @"
Agent: Bosswoman MAYHASAPC overnight monitor
Status: monitor_started
Runtime State: Monitoring the controlled overnight run for $DurationHours hours.
Workers:
$(Get-WorkerSummary)
Verification: Monitor process started and can inspect worker PIDs.
Result: Monitoring active.
Blockers: None.
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: Wait for project receipts and 30-minute monitor updates.
System Hardening Note: Progress monitoring is native and mailbox-only.
"@

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 60
        $now = Get-Date
        $elapsedMinutes = [math]::Round(($now - $started).TotalMinutes, 1)
        $receiptCount = Get-ReceiptCount

        if (-not $noProgressSent -and $elapsedMinutes -ge $NoProgressMinutes -and $receiptCount -eq 0) {
            $noProgressSent = $true
            Send-MonitorReply -Status "blocked" -Severity "blocker" -IdempotencySuffix "no-delivery-progress" -Message @"
Agent: Bosswoman MAYHASAPC overnight monitor
Status: blocked
Runtime State: No project receipt detected after $NoProgressMinutes minutes.
Workers:
$(Get-WorkerSummary)
Verification: Outbox searched for receipts tied to $ReplyTo.
Result: no_delivery_progress
Blockers: Project workers may be hung, crashed, or unable to send receipts.
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should inspect worker logs under $RunDir before launching more workers.
System Hardening Note: Worker fanout remains capped; monitor detected lack of receipts instead of silently assuming progress.
"@
        }

        if (($now - $lastStatus).TotalMinutes -ge $StatusMinutes) {
            $lastStatus = $now
            Send-MonitorReply -Status "in_progress" -Severity "fyi" -IdempotencySuffix "status" -Message @"
Agent: Bosswoman MAYHASAPC overnight monitor
Status: in_progress
Runtime State: elapsed_minutes=$elapsedMinutes; receipt_count=$receiptCount
Workers:
$(Get-WorkerSummary)
Verification: Worker PIDs inspected; mailbox outbox receipt count checked.
Result: Monitor heartbeat.
Blockers: $(if ($noProgressSent) { "No project receipt was found by the $NoProgressMinutes minute mark." } else { "None at monitor level." })
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: Continue until workers return receipts or the 6-hour window ends.
System Hardening Note: Status is mailbox-only; no main chat noise.
"@
        }
    }

    Send-MonitorReply -Status "done" -Severity "fyi" -IdempotencySuffix "complete" -Message @"
Agent: Bosswoman MAYHASAPC overnight monitor
Status: done
Runtime State: $DurationHours hour monitoring window completed.
Workers:
$(Get-WorkerSummary)
Verification: Final worker PID and mailbox receipt check completed.
Result: receipt_count=$(Get-ReceiptCount)
Blockers: $(if ($noProgressSent) { "No project receipt was found by the $NoProgressMinutes minute mark." } else { "None at monitor level." })
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should summarize project receipts and inspect any missing worker logs.
System Hardening Note: Overnight run reached monitor closeout without broad Bossman dispatch.
"@
} catch {
    Write-MonitorLog "Monitor failed: $($_.Exception.Message)"
    try {
        Send-MonitorReply -Status "blocked" -Severity "blocker" -IdempotencySuffix "monitor-failed" -Message @"
Agent: Bosswoman MAYHASAPC overnight monitor
Status: blocked
Runtime State: Monitor failed.
Result: $($_.Exception.Message)
Blockers: Overnight monitor crashed or could not commit its mailbox update.
Owner Button Needed: None.
Commander Approval Needed: None.
Critical Escalation: None.
Next Best Action: AI Manager should inspect $logPath and project worker logs under $RunDir.
System Hardening Note: Monitor failed closed by reporting the failure.
"@
    } catch {
        Write-MonitorLog "Failed to send monitor failure reply: $($_.Exception.Message)"
    }
}
