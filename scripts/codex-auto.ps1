param(
    [switch] $DryRun,
    [switch] $Bounce,
    [switch] $BounceOnly,
    [switch] $Council,
    [switch] $NoCouncil,
    [switch] $ForceCodex,
    [switch] $ForceChatGPT,
    [switch] $NoOptimizeCredits,
    [switch] $NoOpen,
    [switch] $Print,
    [switch] $PacketOnly,
    [string] $Cwd = (Get-Location).Path,
    [string] $Sandbox = "",
    [string] $ApprovalPolicy = "",
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $PromptParts
)

$prompt = ($PromptParts -join " ").Trim()
$tagForceCodex = $false
$tagForceChatGPT = $false
$tagBounce = $false
$tagCouncil = $false
$tagNoCouncil = $false
if ($prompt -match "\[(codex|force-codex)\]" -or $prompt -match "\s--(codex|force-codex)\b") {
    $tagForceCodex = $true
    $prompt = (($prompt -replace "\[(codex|force-codex)\]", "") -replace "\s--(codex|force-codex)\b", "").Trim()
}
if ($prompt -match "\[(chatgpt|gpt|force-chatgpt)\]" -or $prompt -match "\s--(chatgpt|gpt|force-chatgpt)\b") {
    $tagForceChatGPT = $true
    $prompt = (($prompt -replace "\[(chatgpt|gpt|force-chatgpt)\]", "") -replace "\s--(chatgpt|gpt|force-chatgpt)\b", "").Trim()
}
if ($prompt -match "\[(bounce|debate|preflight)\]" -or $prompt -match "\s--(bounce|debate|preflight)\b") {
    $tagBounce = $true
    $prompt = (($prompt -replace "\[(bounce|debate|preflight)\]", "") -replace "\s--(bounce|debate|preflight)\b", "").Trim()
}
if ($prompt -match "\[(council|agents)\]" -or $prompt -match "\s--(council|agents)\b") {
    $tagCouncil = $true
    $prompt = (($prompt -replace "\[(council|agents)\]", "") -replace "\s--(council|agents)\b", "").Trim()
}
if ($prompt -match "\[(nocouncil|no-council|raw|direct)\]" -or $prompt -match "\s--(nocouncil|no-council|raw|direct)\b") {
    $tagNoCouncil = $true
    $prompt = (($prompt -replace "\[(nocouncil|no-council|raw|direct)\]", "") -replace "\s--(nocouncil|no-council|raw|direct)\b", "").Trim()
}
if ($tagBounce) { $Bounce = $true }
if ($tagCouncil) { $Council = $true }
if ($tagNoCouncil) { $NoCouncil = $true }
if ($tagForceCodex) { $ForceCodex = $true }
if ($tagForceChatGPT) { $ForceChatGPT = $true }
if ($BounceOnly) { $Bounce = $true }
if (-not $prompt) {
    Write-Error "Usage: codex-auto.ps1 [-DryRun] [-Bounce] [-BounceOnly] [-Council] [-NoCouncil] [-ForceCodex] [-ForceChatGPT] [-NoOptimizeCredits] [-NoOpen] [-Print] [-PacketOnly] [-Cwd PATH] [-Sandbox MODE] [-ApprovalPolicy POLICY] <task prompt>"
    exit 2
}

$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
Import-Module $modulePath -Force

if (-not $NoOptimizeCredits) {
    $optimizerRoute = Select-AiWorkRoute -Text $prompt -ForceCodex:$ForceCodex -ForceChatGPT:$ForceChatGPT
    $signalText = if ($optimizerRoute.Signals -and $optimizerRoute.Signals.Count -gt 0) {
        $optimizerRoute.Signals -join ", "
    } else {
        "none"
    }

    $codexHome = Split-Path -Parent $PSScriptRoot
    $logDir = Join-Path $codexHome "logs"
    $optimizerLogPath = Join-Path $logDir "ai-credits-optimizer.log"
    New-Item -ItemType Directory -Force $logDir | Out-Null
    $optimizerStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$optimizerStamp] route=$($optimizerRoute.Route) | confidence=$($optimizerRoute.Confidence) | signals=$signalText | $Cwd | $prompt" | Add-Content -Path $optimizerLogPath

    if ($optimizerRoute.Route -eq "chatgpt") {
        Write-Host "AI credits optimizer: ChatGPT route selected"
        Write-Host "Reason: $($optimizerRoute.Reason)"
        Write-Host "Signals: $signalText"
        Write-Host "Return path: chatgpt-return.cmd -Print"
        Write-Host "Logged to: $optimizerLogPath"
        if ($DryRun) {
            Write-Host "Dry run only. Prompt: $prompt"
            exit 0
        }

        $routeScript = Join-Path $PSScriptRoot "chatgpt-route.ps1"
        $routeArgs = @()
        if ($NoOpen) { $routeArgs += "-NoOpen" }
        if ($Print) { $routeArgs += "-Print" }
        if ($PacketOnly) { $routeArgs += "-PacketOnly" }
        $routeArgs += $prompt
        & $routeScript @routeArgs
        exit $LASTEXITCODE
    }

    Write-Host "AI credits optimizer: Codex route selected"
    Write-Host "Reason: $($optimizerRoute.Reason)"
}

$profile = Select-CodexGear -Text $prompt
$gear = Get-CodexGear -Profile $profile

Write-Host "Codex auto gear: $($gear.Profile) ($($gear.Gear))"
Write-Host "Model: $($gear.Model)"
Write-Host "Reasoning effort: $($gear.Effort)"
$tier = if ($gear.ServiceTier) { $gear.ServiceTier } else { "(default/none)" }
Write-Host "Service tier: $tier"
Write-Host "Workspace: $Cwd"
Write-Host "Command: codex $($gear.Command)"
if ($Sandbox) { Write-Host "Sandbox: $Sandbox" }
if ($ApprovalPolicy) { Write-Host "Approval policy: $ApprovalPolicy" }
$autoCouncil = (-not $NoCouncil) -and (-not $Council) -and (-not $BounceOnly) -and (-not $Bounce) -and $gear.Profile -eq "max" -and $gear.Command -eq "exec"
if ($autoCouncil) { $Council = $true }
if ($Council) { $Bounce = $true }
$bounceEnabled = $Bounce -and $gear.Profile -eq "max" -and $gear.Command -eq "exec"
$councilEnabled = $Council -and $gear.Profile -eq "max" -and $gear.Command -eq "exec"
$bounceMode = if ($BounceOnly) { "bounce-only" } elseif ($councilEnabled) { "council-bounce-then-execute" } elseif ($bounceEnabled) { "bounce-then-execute" } elseif ($Bounce) { "requested but skipped; only max/xhigh exec routes bounce" } else { "off" }
Write-Host "Self-bounce: $bounceMode"
Write-Host "Council mode: $(if ($councilEnabled -and $autoCouncil) { "auto-on" } elseif ($councilEnabled) { "on" } elseif ($Council) { "requested but skipped; only max/xhigh exec routes use council" } elseif ($NoCouncil) { "off by explicit override" } else { "off" })"

$codexHome = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $codexHome "logs"
$logPath = Join-Path $logDir "reasoning-gear.log"
New-Item -ItemType Directory -Force $logDir | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] $($gear.Profile)/$($gear.Gear) | model=$($gear.Model) | effort=$($gear.Effort) | tier=$tier | sandbox=$Sandbox | approval=$ApprovalPolicy | bounce=$bounceMode | council=$Council | autoCouncil=$autoCouncil | noCouncil=$NoCouncil | $Cwd | $prompt" | Add-Content -Path $logPath

if ($DryRun) {
    Write-Host "Dry run only. Prompt: $prompt"
    Write-Host "Logged to: $logPath"
    exit 0
}

function Invoke-SelfBounce {
    param(
        [string] $CodexPath,
        [string] $Workspace,
        [string] $TaskPrompt,
        [string] $OutputDir,
        [switch] $CouncilMode
    )

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outFile = Join-Path $OutputDir "xhigh-bounce-$stamp-$PID.md"
    $runLog = Join-Path $OutputDir "xhigh-bounce-$stamp-$PID.run.log"
    if ($CouncilMode) {
        $bouncePrompt = @"
You are the xhigh CEO/CTO preflight council for a Codex implementation task.

Task:
$TaskPrompt

Rules:
- Do not edit files, run commands, commit, push, deploy, or take external actions.
- Think before trying. Produce a better implementation direction before execution starts.
- CEO Agent scopes the requirements, success criteria, user value, and owner-only blockers.
- CTO Agent chooses the technical approach using the existing repo and stack unless there is a strong reason not to.
- Tester/QA Agent predicts likely bugs, missing tests, edge cases, and verification steps before implementation starts.
- End with a concise Programmer Brief: exact first steps, files or areas to inspect, risks, and validation commands.
- If an Owner button or Commander approval would truly be needed, say exactly why.
- Use plain ASCII text only. Avoid smart quotes and special punctuation.
"@
    } else {
        $bouncePrompt = @"
You are the xhigh preflight council for a Codex implementation task.

Task:
$TaskPrompt

Rules:
- Do not edit files, run commands, commit, push, deploy, or take external actions.
- Think before trying. Produce a better implementation direction before execution starts.
- Act as three internal reviewers: Builder, Skeptic, and Verifier.
- Builder proposes 2-3 viable approaches.
- Skeptic points out failure modes, hidden risks, and premature assumptions.
- Verifier defines the smallest useful validation plan.
- End with a concise final recommendation and first implementation steps.
- If an Owner button or Commander approval would truly be needed, say exactly why.
- Use plain ASCII text only. Avoid smart quotes and special punctuation.
"@
    }

    Write-Host "Running xhigh self-bounce preflight..."
    $bouncePrompt | & $CodexPath exec -C $Workspace --sandbox read-only --ephemeral -p max -o $outFile "-" *> $runLog
    $preflightExitCode = $LASTEXITCODE
    if ($preflightExitCode -ne 0) {
        throw "Self-bounce preflight failed with exit code $preflightExitCode. Run log: $runLog"
    }
    if (-not (Test-Path -LiteralPath $outFile)) {
        throw "Self-bounce output was not created: $outFile"
    }

    $bounceText = (Get-Content -LiteralPath $outFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($bounceText)) {
        throw "Self-bounce output was empty: $outFile"
    }

    $requiredMarkers = if ($CouncilMode) {
        @("CEO Agent", "CTO Agent", "Tester/QA Agent", "Programmer Brief")
    } else {
        @("Builder", "Skeptic", "Verifier")
    }
    foreach ($marker in $requiredMarkers) {
        if ($bounceText -notmatch [regex]::Escape($marker)) {
            throw "Self-bounce output missing required marker '$marker'. Output: $outFile. Run log: $runLog"
        }
    }

    Write-Host "Self-bounce output: $outFile"
    Write-Host "Self-bounce run log: $runLog"
    return [pscustomobject]@{
        Path = $outFile
        RunLog = $runLog
        Text = $bounceText
    }
}

$codex = Get-CodexExecutable
$execArgs = @("exec", "-C", $Cwd)
if ($Sandbox -eq "danger-full-access" -and $ApprovalPolicy -eq "never") {
    $execArgs += "--dangerously-bypass-approvals-and-sandbox"
} elseif ($Sandbox) {
    $execArgs += @("--sandbox", $Sandbox)
} elseif ($ApprovalPolicy -eq "never") {
    $execArgs += "--dangerously-bypass-approvals-and-sandbox"
}
$execArgs += @("-p", $profile)
if ($gear.Command -eq "review") {
    $configArgs = New-CodexConfigArgs -Gear $gear
    Push-Location -LiteralPath $Cwd
    try {
        & $codex review @configArgs $prompt
    } finally {
        Pop-Location
    }
} else {
    if ($Bounce -and -not $bounceEnabled) {
        Write-Host "Self-bounce skipped because route is not max/xhigh."
    }

    if ($bounceEnabled) {
        $bounceResult = Invoke-SelfBounce -CodexPath $codex -Workspace $Cwd -TaskPrompt $prompt -OutputDir $logDir -CouncilMode:$councilEnabled
        if ($BounceOnly) {
            Write-Host ""
            Write-Host "Bounce-only mode complete. No implementation was started."
            Write-Host "Read: $($bounceResult.Path)"
            Write-Host ""
            Write-Host "Self-bounce result:"
            Write-Host $bounceResult.Text
            exit 0
        }

        if ($councilEnabled) {
            $promptWithBounce = @"
Original task:
$prompt

XHIGH CEO/CTO PREFLIGHT:
$($bounceResult.Text)

Now execute the task through this staged council workflow:
1. CEO Agent: restate scoped requirements and success criteria.
2. CTO Agent: confirm architecture, stack choices, and risk controls against the current repo.
3. Programmer Agent: implement the smallest correct change set.
4. Tester/QA Agent: review the code, run relevant verification, identify bugs or gaps.
5. If Tester/QA finds bugs, return to Programmer Agent for fixes, then repeat QA until clean or truly blocked.

Use the preflight as planning input, but validate it against the repository before changing files.
"@
        } else {
            $promptWithBounce = @"
Original task:
$prompt

XHIGH SELF-BOUNCE PREFLIGHT:
$($bounceResult.Text)

Now execute the task. Use the preflight as planning input, but validate it against the repository before changing files.
"@
        }
        $promptWithBounce | & $codex @execArgs "-"
    } else {
        & $codex @execArgs $prompt
    }
}
