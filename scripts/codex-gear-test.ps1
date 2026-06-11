param(
    [string] $CodexHome = "",
    [switch] $Smoke
)

$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$ErrorActionPreference = "Stop"
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]

function Write-Pass {
    param([string] $Message)
    Write-Host "PASS $Message"
}

function Write-Warn {
    param([string] $Message)
    $script:Warnings.Add($Message)
    Write-Host "WARN $Message"
}

function Write-Fail {
    param([string] $Message)
    $script:Failures.Add($Message)
    Write-Host "FAIL $Message"
}

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )
    if ($Condition) {
        Write-Pass $Message
    } else {
        Write-Fail $Message
    }
}

function Assert-Equal {
    param(
        [object] $Actual,
        [object] $Expected,
        [string] $Message
    )
    if ($Actual -eq $Expected) {
        Write-Pass "$Message = $Expected"
    } else {
        Write-Fail "$Message expected '$Expected', got '$Actual'"
    }
}

$CodexHome = (Resolve-Path -LiteralPath $CodexHome).Path
$scriptDir = Join-Path $CodexHome "scripts"
$modulePath = Join-Path $scriptDir "CodexGear.psm1"

Write-Host "Codex gear test"
Write-Host "Codex home: $CodexHome"

Assert-True (Test-Path -LiteralPath $modulePath) "CodexGear module exists"
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Fail "Cannot continue without CodexGear.psm1"
    exit 1
}

Import-Module $modulePath -Force

$expected = @(
    [pscustomobject]@{ Profile = "fast"; Gear = "low"; Model = "gpt-5.3-codex-spark"; Effort = "low"; ServiceTier = ""; Command = "exec" },
    [pscustomobject]@{ Profile = "balanced"; Gear = "medium"; Model = "gpt-5.4"; Effort = "medium"; ServiceTier = "fast"; Command = "exec" },
    [pscustomobject]@{ Profile = "deep"; Gear = "high"; Model = "gpt-5.5"; Effort = "high"; ServiceTier = "fast"; Command = "exec" },
    [pscustomobject]@{ Profile = "max"; Gear = "xhigh"; Model = "gpt-5.5"; Effort = "xhigh"; ServiceTier = "fast"; Command = "exec" },
    [pscustomobject]@{ Profile = "review"; Gear = "review"; Model = "codex-auto-review"; Effort = "medium"; ServiceTier = ""; Command = "review" }
)

$requiredScripts = @(
    "ai-credits-optimizer.cmd",
    "ai-credits-optimizer.ps1",
    "chatgpt-route.cmd",
    "chatgpt-route.ps1",
    "chatgpt-return.cmd",
    "chatgpt-return.ps1",
    "codex-auto.cmd",
    "codex-auto.ps1",
    "codex-bounce.cmd",
    "codex-council.cmd",
    "codex-doctor.cmd",
    "codex-doctor.ps1",
    "codex-gear.cmd",
    "codex-gear.ps1",
    "codex-gear-test.cmd",
    "codex-gear-test.ps1",
    "codex-notify-router.cmd",
    "codex-notify-router.ps1",
    "codex-project-rules.cmd",
    "codex-project-rules.ps1",
    "codex-project-freshness.cmd",
    "codex-project-freshness.ps1",
    "codex-systems-status.cmd",
    "codex-systems-status.ps1",
    "zdh-worker-boss-interval.cmd",
    "zdh-worker-boss-interval.ps1",
    "codex-low.cmd",
    "codex-medium.cmd",
    "codex-high.cmd",
    "codex-xhigh.cmd",
    "codex-xhigh-bounce.cmd",
    "codex-xhigh-raw.cmd",
    "codex-review.cmd",
    "CodexGear.psm1"
)

foreach ($scriptName in $requiredScripts) {
    Assert-True (Test-Path -LiteralPath (Join-Path $scriptDir $scriptName)) "Script exists: $scriptName"
}

$matrix = Get-CodexGearMatrix
foreach ($item in $expected) {
    $gear = Get-CodexGear -Profile $item.Profile
    Assert-Equal $gear.Gear $item.Gear "$($item.Profile) gear"
    Assert-Equal $gear.Model $item.Model "$($item.Profile) model"
    Assert-Equal $gear.Effort $item.Effort "$($item.Profile) effort"
    Assert-Equal $gear.ServiceTier $item.ServiceTier "$($item.Profile) service tier"
    Assert-Equal $gear.Command $item.Command "$($item.Profile) command"

    $profilePath = Join-Path $CodexHome "$($item.Profile).config.toml"
    Assert-True (Test-Path -LiteralPath $profilePath) "Profile file exists: $($item.Profile).config.toml"
    if (Test-Path -LiteralPath $profilePath) {
        $profileText = Get-Content -LiteralPath $profilePath -Raw
        Assert-True ($profileText -match "model\s*=\s*`"$([regex]::Escape($item.Model))`"") "$($item.Profile) profile model line"
        Assert-True ($profileText -match "model_reasoning_effort\s*=\s*`"$([regex]::Escape($item.Effort))`"") "$($item.Profile) profile effort line"
        Assert-True ($profileText -match "service_tier\s*=\s*`"$([regex]::Escape($item.ServiceTier))`"") "$($item.Profile) profile service tier line"
    }
}

$routeTests = @(
    [pscustomobject]@{ Prompt = "fix typo in README"; Profile = "fast" },
    [pscustomobject]@{ Prompt = "add dashboard panel"; Profile = "balanced" },
    [pscustomobject]@{ Prompt = "debug failing tests"; Profile = "deep" },
    [pscustomobject]@{ Prompt = "change auth billing database permissions"; Profile = "max" },
    [pscustomobject]@{ Prompt = "[review] code review current diff"; Profile = "review" },
    [pscustomobject]@{ Prompt = "[xhigh] change database migration"; Profile = "max" },
    [pscustomobject]@{ Prompt = "[low] show git status"; Profile = "fast" }
)

foreach ($case in $routeTests) {
    Assert-Equal (Select-CodexGear -Text $case.Prompt) $case.Profile "Route '$($case.Prompt)'"
}

$workRouteTests = @(
    [pscustomobject]@{ Prompt = "draft a concise apology email to a client"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "brainstorm ten domain names for a comedy newsletter"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "summarize meeting notes into decisions and action items"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "research competitor positioning for boutique web design agencies"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "translate this short paragraph into Hebrew"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "I need 4 logos for different clients ZDH Sales worked with"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "brainstorm four logo concepts for ZDH Sales clients"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "Create 4 fictional logo concepts/images for a ZDH Sales bridge test. Make up client names. Return a CODEX_RETURN_PACKET."; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "make up four client logos for a bridge test and generate a logo image sheet"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "create actual images in ChatGPT for fictional client logo concepts"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "fix failing tests in the checkout flow"; Route = "codex" },
    [pscustomobject]@{ Prompt = "summarize src/app.ts"; Route = "codex" },
    [pscustomobject]@{ Prompt = "summarize my Gmail inbox for urgent replies"; Route = "codex" },
    [pscustomobject]@{ Prompt = "draft an email using the notes in C:\Repos\client\notes.md"; Route = "codex" },
    [pscustomobject]@{ Prompt = "export four logo SVG files to the assets folder"; Route = "codex" },
    [pscustomobject]@{ Prompt = "download the generated ChatGPT logo image into the project folder"; Route = "codex" },
    [pscustomobject]@{ Prompt = "[low] draft a short email"; Route = "codex" },
    [pscustomobject]@{ Prompt = "[chatgpt] fix failing tests in the checkout flow"; Route = "chatgpt" },
    [pscustomobject]@{ Prompt = "[codex] draft a short email"; Route = "codex" }
)

foreach ($case in $workRouteTests) {
    $workRoute = Select-AiWorkRoute -Text $case.Prompt
    Assert-Equal $workRoute.Route $case.Route "Work route '$($case.Prompt)'"
}

$optimizerDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -NoOpen -Cwd $CodexHome "draft a concise apology email to a client" 2>&1 6>&1 | Out-String)
Assert-True ($optimizerDryRun -match "AI credits optimizer: ChatGPT route selected") "Codex auto dry-run diverts writing task to ChatGPT"
Assert-True ($optimizerDryRun -notmatch "Codex auto gear:") "ChatGPT dry-run does not launch Codex gear"

$optimizerCodexDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -Cwd $CodexHome "fix failing tests in the checkout flow" 2>&1 6>&1 | Out-String)
Assert-True ($optimizerCodexDryRun -match "AI credits optimizer: Codex route selected") "Codex auto dry-run keeps test/debug task in Codex"
Assert-True ($optimizerCodexDryRun -match "Codex auto gear:") "Codex dry-run still selects Codex gear"

$routePrint = (& (Join-Path $scriptDir "chatgpt-route.ps1") -NoOpen -Print -PacketOnly "draft a short client update" 2>&1 6>&1 | Out-String)
Assert-True ($routePrint -match "Return only the CODEX_RETURN_PACKET block") "ChatGPT route packet-only prompt is explicit"
Assert-True ($routePrint -match "Go back to Codex\?:") "ChatGPT route includes go-back field"

$packetFile = Join-Path $env:TEMP "chatgpt-return-packet-$PID.txt"
@"
Useful answer.

CODEX_RETURN_PACKET
Summary: Drafted update.
Decisions: Use concise tone.
Deliverable: Hello client.
Codex next action: none
Files/assets needed: none
Owner buttons needed: none
Confidence: high
Go back to Codex?: no
END_CODEX_RETURN_PACKET
"@ | Set-Content -LiteralPath $packetFile -Encoding UTF8
$returnJson = (& (Join-Path $scriptDir "chatgpt-return.ps1") -InputFile $packetFile -Project "gear-test" -Json 2>&1 6>&1 | Out-String)
Assert-True ($returnJson -match '"HasPacket":\s*true') "ChatGPT return JSON detects packet"
Assert-True ($returnJson -match '"Codex next action":\s*"none"') "ChatGPT return JSON parses next action"

$bounceDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -Bounce -Cwd $CodexHome "[xhigh] change auth permissions" 2>&1 6>&1 | Out-String)
Assert-True ($bounceDryRun -match "Self-bounce: bounce-then-execute") "Bounce dry-run enables max preflight"

$bounceOnlyDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -BounceOnly -Cwd $CodexHome "change auth permissions" 2>&1 6>&1 | Out-String)
Assert-True ($bounceOnlyDryRun -match "Self-bounce: bounce-only") "BounceOnly dry-run enables max preflight"

$councilDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -Council -Cwd $CodexHome "[xhigh] build billing-safe workflow" 2>&1 6>&1 | Out-String)
Assert-True ($councilDryRun -match "Self-bounce: council-bounce-then-execute") "Council dry-run enables xhigh council preflight"
Assert-True ($councilDryRun -match "Council mode: on") "Council dry-run reports council mode"

$autoCouncilDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -Cwd $CodexHome "change auth billing database permissions" 2>&1 6>&1 | Out-String)
Assert-True ($autoCouncilDryRun -match "Self-bounce: council-bounce-then-execute") "Auto xhigh dry-run enforces council preflight"
Assert-True ($autoCouncilDryRun -match "Council mode: auto-on") "Auto xhigh dry-run reports auto council"

$noCouncilDryRun = (& (Join-Path $scriptDir "codex-auto.ps1") -DryRun -NoCouncil -Cwd $CodexHome "[xhigh] change auth permissions" 2>&1 6>&1 | Out-String)
Assert-True ($noCouncilDryRun -match "Self-bounce: off") "NoCouncil dry-run disables auto council preflight"
Assert-True ($noCouncilDryRun -match "Council mode: off by explicit override") "NoCouncil dry-run reports explicit override"

$freshnessDryRun = (& (Join-Path $scriptDir "codex-project-freshness.ps1") -CodexHome $CodexHome -NoUpdateLabels -ProjectPath $CodexHome -Json 2>&1 6>&1 | Out-String)
Assert-True ($freshnessDryRun -match '"Status"') "Project freshness report returns status"

try {
    $codex = Get-CodexExecutable
    Write-Pass "Codex executable found: $codex"
} catch {
    Write-Warn $_.Exception.Message
}

if ($Smoke) {
    try {
        $codex = Get-CodexExecutable
        $outFile = Join-Path $env:TEMP "codex-gear-smoke-$PID.txt"
        if (Test-Path -LiteralPath $outFile) {
            Remove-Item -LiteralPath $outFile -Force
        }
        & $codex exec -C $CodexHome --skip-git-repo-check -p fast -o $outFile "Return exactly: codex-gear-smoke-ok"
        $exitCode = $LASTEXITCODE
        $message = if (Test-Path -LiteralPath $outFile) { (Get-Content -LiteralPath $outFile -Raw).Trim() } else { "" }
        Assert-Equal $exitCode 0 "Smoke exit code"
        Assert-Equal $message "codex-gear-smoke-ok" "Smoke output"
    } catch {
        Write-Fail "Smoke test failed: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Codex gear test summary"
Write-Host "Failures: $($script:Failures.Count)"
Write-Host "Warnings: $($script:Warnings.Count)"

if ($script:Failures.Count -gt 0) {
    exit 1
}

exit 0
