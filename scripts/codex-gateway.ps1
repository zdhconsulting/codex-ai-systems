param(
    [string] $Project = "Gateway",
    [string] $OutDir = "",
    [string] $Cwd = (Get-Location).Path,
    [switch] $DryRun,
    [switch] $Json,
    [switch] $ForceChatGPT,
    [switch] $ForceCodex,
    [switch] $NoOpen,
    [switch] $PacketOnly,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Task
)

$ErrorActionPreference = "Stop"
$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: codex-gateway.cmd [-DryRun] [-ForceChatGPT] [-ForceCodex] [-Project NAME] [-OutDir DIR] `"TASK`""
    Write-Host "Routes high-confidence detachable work to ChatGPT, keeps local/risky work in Codex, and flags mixed work as hybrid."
    exit 1
}

$codexHome = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
$chatGptAutoRoute = Join-Path $PSScriptRoot "chatgpt-auto-route.ps1"
$codexAuto = Join-Path $PSScriptRoot "codex-auto.ps1"
$eventsDir = Join-Path $codexHome "logs\chatgpt-bridge"
$eventsPath = Join-Path $eventsDir "events.jsonl"

Import-Module $modulePath -Force

function ConvertTo-SignalText {
    param([object[]] $Signals)
    if ($Signals -and $Signals.Count -gt 0) {
        return ($Signals -join ", ")
    }
    return "none"
}

function Write-GatewayEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
    ($Event | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $eventsPath -Encoding UTF8
}

function Write-GatewayResult {
    param(
        [object] $Result,
        [switch] $AsJson
    )

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 8
        return
    }

    Write-Host "Codex gateway"
    Write-Host "Route: $($Result.Route)"
    Write-Host "Dispatch: $($Result.Dispatch)"
    Write-Host "Confidence: $($Result.Confidence)"
    Write-Host "Ask first: $($Result.AskFirst)"
    Write-Host "Reason: $($Result.Reason)"
    Write-Host "ChatGPT signals: $(ConvertTo-SignalText $Result.ChatGPTSignals)"
    Write-Host "Codex signals: $(ConvertTo-SignalText $Result.CodexSignals)"
    Write-Host "Next action: $($Result.NextAction)"
    if ($Result.CodexFallbackProfile) {
        Write-Host "Codex fallback: $($Result.CodexFallbackProfile)"
    }
    if ($Result.SessionPath) {
        Write-Host "Session: $($Result.SessionPath)"
    }
    if ($Result.ExitCode -ne $null) {
        Write-Host "Dispatch exit code: $($Result.ExitCode)"
    }
}

$gatewayRoute = Select-ChatGatewayRoute -Text $taskText -ForceChatGPT:$ForceChatGPT -ForceCodex:$ForceCodex
$fallbackProfile = Select-CodexGear -Text $taskText
$routeResult = [ordered]@{
    Route = $gatewayRoute.Route
    Dispatch = $gatewayRoute.Dispatch
    Confidence = $gatewayRoute.Confidence
    AskFirst = $gatewayRoute.AskFirst
    Reason = $gatewayRoute.Reason
    NextAction = $gatewayRoute.NextAction
    ChatGPTSignals = $gatewayRoute.ChatGPTSignals
    CodexSignals = $gatewayRoute.CodexSignals
    CodexFallbackProfile = $fallbackProfile
    Project = $Project
    Cwd = $Cwd
    Task = $taskText
}

Write-GatewayEvent ([ordered]@{
    type = "gateway-classified"
    at = (Get-Date).ToString("o")
    project = $Project
    cwd = $Cwd
    task = $taskText
    route = $gatewayRoute.Route
    dispatch = $gatewayRoute.Dispatch
    confidence = $gatewayRoute.Confidence
    askFirst = $gatewayRoute.AskFirst
    reason = $gatewayRoute.Reason
    chatgptSignals = $gatewayRoute.ChatGPTSignals
    codexSignals = $gatewayRoute.CodexSignals
    codexFallbackProfile = $fallbackProfile
})

if ($DryRun) {
    $routeResult.Status = "dry-run"
    Write-GatewayResult -Result ([pscustomobject]$routeResult) -AsJson:$Json
    exit 0
}

if ($gatewayRoute.Route -eq "hybrid") {
    $routeResult.Status = "ask-first"
    Write-GatewayEvent ([ordered]@{
        type = "gateway-ask-first"
        at = (Get-Date).ToString("o")
        project = $Project
        task = $taskText
        reason = $gatewayRoute.Reason
        route = "hybrid"
    })
    Write-GatewayResult -Result ([pscustomobject]$routeResult) -AsJson:$Json
    exit 0
}

if ($gatewayRoute.Route -eq "chatgpt") {
    $chatGptParams = @{
        Project = $Project
        ForceChatGPT = $true
    }
    if ($OutDir) { $chatGptParams.OutDir = $OutDir }
    if ($NoOpen) { $chatGptParams.NoOpen = $true }
    if ($PacketOnly) { $chatGptParams.PacketOnly = $true }

    & $chatGptAutoRoute @chatGptParams $taskText
    $exitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
    $routeResult.Status = "dispatched"
    $routeResult.ExitCode = $exitCode

    Write-GatewayEvent ([ordered]@{
        type = "gateway-dispatched"
        at = (Get-Date).ToString("o")
        project = $Project
        task = $taskText
        route = "chatgpt"
        dispatch = "chatgpt-auto-route"
        exitCode = $exitCode
        avoidedCodexCreativeWork = $true
    })
    exit $exitCode
}

$codexArgs = @("-NoOptimizeCredits", "-Cwd", $Cwd)
if ($ForceCodex) { $codexArgs += "-ForceCodex" }
$codexArgs += $taskText

& $codexAuto @codexArgs
$codexExitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
$routeResult.Status = "dispatched"
$routeResult.ExitCode = $codexExitCode

Write-GatewayEvent ([ordered]@{
    type = "gateway-dispatched"
    at = (Get-Date).ToString("o")
    project = $Project
    cwd = $Cwd
    task = $taskText
    route = "codex"
    dispatch = "codex-auto"
    exitCode = $codexExitCode
    avoidedCodexCreativeWork = $false
})
exit $codexExitCode
