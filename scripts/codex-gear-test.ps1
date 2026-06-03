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
    "chatgpt-route.cmd",
    "chatgpt-route.ps1",
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
    "codex-project-freshness.cmd",
    "codex-project-freshness.ps1",
    "codex-systems-status.cmd",
    "codex-systems-status.ps1",
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
