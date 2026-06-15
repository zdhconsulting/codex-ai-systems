param(
    [string] $Project = "Gateway",
    [string] $OutDir = "",
    [string] $Cwd = (Get-Location).Path,
    [int] $CacheTtlDays = 14,
    [switch] $DryRun,
    [switch] $Json,
    [switch] $ForceChatGPT,
    [switch] $ForceCodex,
    [switch] $NoOpen,
    [switch] $PacketOnly,
    [switch] $NoCache,
    [switch] $Refresh,
    [switch] $SplitHybrid,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Task
)

$ErrorActionPreference = "Stop"
$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: codex-gateway.cmd [-DryRun] [-ForceChatGPT] [-ForceCodex] [-Refresh] [-SplitHybrid] [-Project NAME] [-OutDir DIR] `"TASK`""
    Write-Host "Routes high-confidence detachable work to ChatGPT, keeps local/risky work in Codex, flags mixed work as hybrid, and reuses exact cached ChatGPT packets when safe."
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

function New-CacheSummary {
    param([object] $Cache)

    $entry = if ($Cache) { $Cache.Entry } else { $null }
    $assetCount = 0
    if ($entry -and $entry.Assets) {
        $assetCount = @($entry.Assets).Count
    } elseif ($entry -and $entry.AssetCount) {
        $assetCount = [int]$entry.AssetCount
    }

    return [ordered]@{
        Status = if ($Cache) { $Cache.Status } else { "disabled" }
        Hit = if ($Cache) { [bool]$Cache.Hit } else { $false }
        Key = if ($Cache) { $Cache.Key } else { "" }
        Path = if ($Cache) { $Cache.Path } else { "" }
        Reason = if ($Cache) { $Cache.Reason } else { "Cache lookup disabled." }
        HandoffPath = if ($entry -and $entry.HandoffPath) { $entry.HandoffPath } else { "" }
        ResponsePath = if ($entry -and $entry.ResponsePath) { $entry.ResponsePath } else { "" }
        OutputDir = if ($entry -and $entry.OutputDir) { $entry.OutputDir } else { "" }
        AssetCount = $assetCount
        CompletedAt = if ($entry -and $entry.CompletedAt) { $entry.CompletedAt } else { "" }
    }
}

function Write-GatewayEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
    ($Event | ConvertTo-Json -Compress -Depth 10) | Add-Content -LiteralPath $eventsPath -Encoding UTF8
}

function Write-GatewayResult {
    param(
        [object] $Result,
        [switch] $AsJson
    )

    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 10
        return
    }

    Write-Host "Codex gateway"
    Write-Host "Status: $($Result.Status)"
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
    if ($Result.SavingsEstimate) {
        Write-Host "Savings estimate: $($Result.SavingsEstimate.EstimatedAvoidedCodexTokens) Codex tokens / $($Result.SavingsEstimate.AvoidedCodexTurns) turn(s) avoided ($($Result.SavingsEstimate.Basis))"
    }
    if ($Result.CodexUsageBefore -and $null -ne $Result.CodexUsageBefore.PrimaryUsedPercent) {
        Write-Host "Codex usage before: primary $($Result.CodexUsageBefore.PrimaryUsedPercent)% / secondary $($Result.CodexUsageBefore.SecondaryUsedPercent)%"
    } elseif ($Result.CodexUsageBefore) {
        Write-Host "Codex usage before: telemetry found, rate-limit percentages unavailable"
    }
    if ($Result.Cache) {
        Write-Host "Cache: $($Result.Cache.Status) ($($Result.Cache.Reason))"
        if ($Result.Cache.Hit) {
            if ($Result.Cache.HandoffPath) { Write-Host "Cached handoff: $($Result.Cache.HandoffPath)" }
            if ($Result.Cache.OutputDir) { Write-Host "Cached assets: $($Result.Cache.OutputDir)" }
            Write-Host "Cached asset count: $($Result.Cache.AssetCount)"
        }
    }
    if ($Result.HybridSplit) {
        Write-Host "Hybrid ChatGPT task: $($Result.HybridSplit.ChatGPTTask)"
        Write-Host "Hybrid Codex follow-up: $($Result.HybridSplit.CodexTask)"
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
$taskKey = Get-ChatGatewayTaskKey -Text $taskText -Project $Project
$cache = $null
if (-not $NoCache -and -not $Refresh -and $gatewayRoute.Route -eq "chatgpt") {
    $cache = Get-ChatGatewayCacheEntry -CodexHome $codexHome -Task $taskText -Project $Project -TtlDays $CacheTtlDays
} elseif ($NoCache) {
    $cache = [pscustomobject]@{
        Hit = $false
        Status = "disabled"
        Reason = "Cache disabled by -NoCache."
        Key = $taskKey
        Path = Join-Path $codexHome "cache\chatgpt-bridge\$taskKey.json"
        Entry = $null
    }
} elseif ($Refresh -and $gatewayRoute.Route -eq "chatgpt") {
    $cache = [pscustomobject]@{
        Hit = $false
        Status = "refresh"
        Reason = "Refresh requested; cached result will not be reused."
        Key = $taskKey
        Path = Join-Path $codexHome "cache\chatgpt-bridge\$taskKey.json"
        Entry = $null
    }
}

$cacheSummary = New-CacheSummary -Cache $cache
$savingsEstimate = Get-ChatGatewaySavingsEstimate `
    -Text $taskText `
    -Route $gatewayRoute.Route `
    -ChatGPTSignals $gatewayRoute.ChatGPTSignals `
    -CodexFallbackProfile $fallbackProfile `
    -CacheHit:($cacheSummary.Hit)
$codexUsageBefore = Get-CodexLatestTokenSnapshot -CodexHome $codexHome
$hybridSplit = if ($gatewayRoute.Route -eq "hybrid") { New-ChatGatewayHybridSplit -Text $taskText } else { $null }

$routeResult = [ordered]@{
    Status = if ($DryRun) { "dry-run" } else { "classified" }
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
    TaskKey = $taskKey
    Cache = $cacheSummary
    SavingsEstimate = $savingsEstimate
    CodexUsageBefore = $codexUsageBefore
}
if ($hybridSplit) {
    $routeResult["HybridSplit"] = $hybridSplit
}

Write-GatewayEvent ([ordered]@{
    type = "gateway-classified"
    at = (Get-Date).ToString("o")
    project = $Project
    cwd = $Cwd
    task = $taskText
    taskKey = $taskKey
    route = $gatewayRoute.Route
    dispatch = $gatewayRoute.Dispatch
    confidence = $gatewayRoute.Confidence
    askFirst = $gatewayRoute.AskFirst
    reason = $gatewayRoute.Reason
    chatgptSignals = $gatewayRoute.ChatGPTSignals
    codexSignals = $gatewayRoute.CodexSignals
    codexFallbackProfile = $fallbackProfile
    cache = $cacheSummary
    savingsEstimate = $savingsEstimate
    codexUsageBefore = $codexUsageBefore
    hybridSplit = $hybridSplit
})

if ($DryRun) {
    Write-GatewayResult -Result ([pscustomobject]$routeResult) -AsJson:$Json
    exit 0
}

if ($gatewayRoute.Route -eq "chatgpt" -and $cacheSummary.Hit) {
    $routeResult["Status"] = "cache-hit"
    $routeResult["Dispatch"] = "cache"
    $routeResult["NextAction"] = "Reuse the cached ChatGPT packet/assets. Use -Refresh to force a new ChatGPT run."

    Write-GatewayEvent ([ordered]@{
        type = "gateway-cache-hit"
        at = (Get-Date).ToString("o")
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "chatgpt"
        cache = $cacheSummary
        avoidedCodexCreativeWork = $true
        avoidedChatGptRun = $true
        savingsEstimate = $savingsEstimate
        codexUsageBefore = $codexUsageBefore
    })

    Write-GatewayResult -Result ([pscustomobject]$routeResult) -AsJson:$Json
    exit 0
}

if ($gatewayRoute.Route -eq "hybrid") {
    if (-not $SplitHybrid) {
        $routeResult["Status"] = "ask-first"
        Write-GatewayEvent ([ordered]@{
            type = "gateway-ask-first"
            at = (Get-Date).ToString("o")
            project = $Project
            task = $taskText
            taskKey = $taskKey
            reason = $gatewayRoute.Reason
            route = "hybrid"
            hybridSplit = $hybridSplit
        })
        Write-GatewayResult -Result ([pscustomobject]$routeResult) -AsJson:$Json
        exit 0
    }

    $chatGptParams = @{
        Project = $Project
        ForceChatGPT = $true
        PacketOnly = $true
    }
    if ($OutDir) { $chatGptParams.OutDir = $OutDir }
    if ($NoOpen) { $chatGptParams.NoOpen = $true }
    if ($PacketOnly) { $chatGptParams.PacketOnly = $true }

    & $chatGptAutoRoute @chatGptParams $hybridSplit.ChatGPTTask
    $splitSucceeded = $?
    $splitExitCode = if ($splitSucceeded) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
    $routeResult["Status"] = "hybrid-chatgpt-dispatched"
    $routeResult["Dispatch"] = "chatgpt-auto-route"
    $routeResult["ExitCode"] = $splitExitCode

    Write-GatewayEvent ([ordered]@{
        type = "gateway-dispatched"
        at = (Get-Date).ToString("o")
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "hybrid"
        dispatch = "chatgpt-auto-route"
        exitCode = $splitExitCode
        hybridSplit = $hybridSplit
        avoidedCodexCreativeWork = $true
        savingsEstimate = $savingsEstimate
    })
    exit $splitExitCode
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
    $chatSucceeded = $?
    $exitCode = if ($chatSucceeded) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
    $routeResult["Status"] = "dispatched"
    $routeResult["ExitCode"] = $exitCode

    Write-GatewayEvent ([ordered]@{
        type = "gateway-dispatched"
        at = (Get-Date).ToString("o")
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "chatgpt"
        dispatch = "chatgpt-auto-route"
        exitCode = $exitCode
        avoidedCodexCreativeWork = $true
        avoidedChatGptRun = $false
        savingsEstimate = $savingsEstimate
        codexUsageBefore = $codexUsageBefore
    })
    exit $exitCode
}

$codexArgs = @("-NoOptimizeCredits", "-Cwd", $Cwd)
if ($ForceCodex) { $codexArgs += "-ForceCodex" }
$codexArgs += $taskText

& $codexAuto @codexArgs
$codexSucceeded = $?
$codexExitCode = if ($codexSucceeded) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
$routeResult["Status"] = "dispatched"
$routeResult["ExitCode"] = $codexExitCode

Write-GatewayEvent ([ordered]@{
    type = "gateway-dispatched"
    at = (Get-Date).ToString("o")
    project = $Project
    cwd = $Cwd
    task = $taskText
    taskKey = $taskKey
    route = "codex"
    dispatch = "codex-auto"
    exitCode = $codexExitCode
    avoidedCodexCreativeWork = $false
    savingsEstimate = $savingsEstimate
    codexUsageBefore = $codexUsageBefore
})
exit $codexExitCode
