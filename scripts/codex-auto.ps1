param(
    [switch] $DryRun,
    [switch] $Bounce,
    [switch] $BounceOnly,
    [string] $Cwd = (Get-Location).Path,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $PromptParts
)

$prompt = ($PromptParts -join " ").Trim()
$tagBounce = $false
if ($prompt -match "\[(bounce|debate|preflight)\]" -or $prompt -match "\s--(bounce|debate|preflight)\b") {
    $tagBounce = $true
    $prompt = (($prompt -replace "\[(bounce|debate|preflight)\]", "") -replace "\s--(bounce|debate|preflight)\b", "").Trim()
}
if ($tagBounce) { $Bounce = $true }
if ($BounceOnly) { $Bounce = $true }
if (-not $prompt) {
    Write-Error "Usage: codex-auto.ps1 [-DryRun] [-Bounce] [-BounceOnly] [-Cwd PATH] <task prompt>"
    exit 2
}

$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
Import-Module $modulePath -Force

$profile = Select-CodexGear -Text $prompt
$gear = Get-CodexGear -Profile $profile

Write-Host "Codex auto gear: $($gear.Profile) ($($gear.Gear))"
Write-Host "Model: $($gear.Model)"
Write-Host "Reasoning effort: $($gear.Effort)"
$tier = if ($gear.ServiceTier) { $gear.ServiceTier } else { "(default/none)" }
Write-Host "Service tier: $tier"
Write-Host "Workspace: $Cwd"
Write-Host "Command: codex $($gear.Command)"
$bounceEnabled = $Bounce -and $gear.Profile -eq "max" -and $gear.Command -eq "exec"
$bounceMode = if ($BounceOnly) { "bounce-only" } elseif ($bounceEnabled) { "bounce-then-execute" } elseif ($Bounce) { "requested but skipped; only max/xhigh exec routes bounce" } else { "off" }
Write-Host "Self-bounce: $bounceMode"

$codexHome = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $codexHome "logs"
$logPath = Join-Path $logDir "reasoning-gear.log"
New-Item -ItemType Directory -Force $logDir | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] $($gear.Profile)/$($gear.Gear) | model=$($gear.Model) | effort=$($gear.Effort) | tier=$tier | bounce=$bounceMode | $Cwd | $prompt" | Add-Content -Path $logPath

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
        [string] $OutputDir
    )

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outFile = Join-Path $OutputDir "xhigh-bounce-$stamp-$PID.md"
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
"@

    Write-Host "Running xhigh self-bounce preflight..."
    $bouncePrompt | & $CodexPath exec -C $Workspace --sandbox read-only --ephemeral -p max -o $outFile "-"
    if ($LASTEXITCODE -ne 0) {
        throw "Self-bounce preflight failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $outFile)) {
        throw "Self-bounce output was not created: $outFile"
    }

    $bounceText = (Get-Content -LiteralPath $outFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($bounceText)) {
        throw "Self-bounce output was empty: $outFile"
    }

    Write-Host "Self-bounce output: $outFile"
    return [pscustomobject]@{
        Path = $outFile
        Text = $bounceText
    }
}

$codex = Get-CodexExecutable
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
        $bounce = Invoke-SelfBounce -CodexPath $codex -Workspace $Cwd -TaskPrompt $prompt -OutputDir $logDir
        if ($BounceOnly) {
            Write-Host ""
            Write-Host "Bounce-only mode complete. No implementation was started."
            Write-Host "Read: $($bounce.Path)"
            exit 0
        }

        $promptWithBounce = @"
Original task:
$prompt

XHIGH SELF-BOUNCE PREFLIGHT:
$($bounce.Text)

Now execute the task. Use the preflight as planning input, but validate it against the repository before changing files.
"@
        $promptWithBounce | & $codex exec -C $Cwd -p $profile "-"
    } else {
        & $codex exec -C $Cwd -p $profile $prompt
    }
}
