param(
    [switch] $DryRun,
    [switch] $Json,
    [switch] $ForceCodex,
    [switch] $ForceChatGPT,
    [switch] $NoOpen,
    [switch] $Print,
    [string] $Cwd = (Get-Location).Path,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $PromptParts
)

$ErrorActionPreference = "Stop"
$prompt = ($PromptParts -join " ").Trim()
if (-not $prompt) {
    Write-Host "Usage: ai-credits-optimizer.cmd [-DryRun] [-Json] [-ForceCodex] [-ForceChatGPT] [-NoOpen] [-Print] [-Cwd PATH] `"TASK`""
    Write-Host "Routes obvious non-repo writing, strategy, summary, and design-direction tasks to ChatGPT; keeps code/local/tooling work in Codex."
    exit 1
}

$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
Import-Module $modulePath -Force

$route = Select-AiWorkRoute -Text $prompt -ForceCodex:$ForceCodex -ForceChatGPT:$ForceChatGPT
$gear = Get-CodexGear -Profile (Select-CodexGear -Text $prompt)
$signalText = if ($route.Signals -and $route.Signals.Count -gt 0) {
    $route.Signals -join ", "
} else {
    "none"
}

$result = [pscustomobject]@{
    Route = $route.Route
    Reason = $route.Reason
    Confidence = $route.Confidence
    Signals = $route.Signals
    CodexFallbackProfile = $gear.Profile
    CodexFallbackGear = $gear.Gear
    CodexFallbackModel = $gear.Model
    Cwd = $Cwd
    Prompt = $prompt
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host "AI credits optimizer"
Write-Host "Work route: $($route.Route)"
Write-Host "Reason: $($route.Reason)"
Write-Host "Confidence: $($route.Confidence)"
Write-Host "Signals: $signalText"
Write-Host "Codex fallback: $($gear.Profile) ($($gear.Gear), $($gear.Model))"
Write-Host "Workspace: $Cwd"

if ($DryRun) {
    Write-Host "Dry run only. No route launched."
    exit 0
}

if ($route.Route -eq "chatgpt") {
    $routeScript = Join-Path $PSScriptRoot "chatgpt-route.ps1"
    $routeArgs = @()
    if ($NoOpen) { $routeArgs += "-NoOpen" }
    if ($Print) { $routeArgs += "-Print" }
    $routeArgs += $prompt
    & $routeScript @routeArgs
    exit $LASTEXITCODE
}

$codexScript = Join-Path $PSScriptRoot "codex-auto.ps1"
& $codexScript -NoOptimizeCredits -Cwd $Cwd $prompt
exit $LASTEXITCODE
