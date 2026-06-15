param(
    [string] $Project = "Gateway",
    [string] $OutDir = "",
    [string] $Cwd = (Get-Location).Path,
    [int] $CacheTtlDays = 14,
    [int] $ProviderReadyTimeoutSeconds = 30,
    [switch] $DryRun,
    [switch] $Json,
    [switch] $ForceChatGPT,
    [switch] $ForceCodex,
    [switch] $AllowProviderFallback,
    [switch] $FirmProvider,
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

function ConvertTo-PowerShellSingleQuotedArgument {
    param([string] $Value)
    return "'" + ($Value -replace "'", "''") + "'"
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
    $line = $Event | ConvertTo-Json -Compress -Depth 10
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $line | Add-Content -LiteralPath $eventsPath -Encoding UTF8
            return
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
    Write-Warning "Could not append gateway event after retries: $eventsPath"
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
    if ($Result.ProviderFallbackPolicy) {
        $policy = $Result.ProviderFallbackPolicy
        $mode = if ($policy.Firm) { "firm" } else { "soft" }
        $fallbackText = if ($policy.CodexFallbackAllowed) { "Codex fallback allowed after $($policy.ProviderReadyTimeoutSeconds)s readiness failure" } else { "no automatic Codex fallback" }
        Write-Host "Provider route: $mode ($fallbackText)"
        if ($policy.CodexFallbackCommand) { Write-Host "Fallback command: $($policy.CodexFallbackCommand)" }
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

$firmProviderTag = $taskText.ToLowerInvariant() -match "\[(firm-provider|provider-required|no-provider-fallback|strict-provider)\]" -or
    $taskText.ToLowerInvariant() -match "\s--(firm-provider|provider-required|no-provider-fallback|strict-provider)\b"
$forceChatGptTag = $taskText.ToLowerInvariant() -match "\[(chatgpt|gpt|force-chatgpt)\]" -or
    $taskText.ToLowerInvariant() -match "\s--(chatgpt|gpt|force-chatgpt)\b"
$providerReadyTimeoutSeconds = [Math]::Max(5, $ProviderReadyTimeoutSeconds)
$providerFirm = [bool]($FirmProvider -or $firmProviderTag -or (($ForceChatGPT -or $forceChatGptTag) -and -not $AllowProviderFallback))
$codexFallbackAllowed = -not $providerFirm
$codexFallbackCommand = if ($codexFallbackAllowed) {
    "& $(ConvertTo-PowerShellSingleQuotedArgument $codexAuto) -ForceCodex -NoOptimizeCredits -Cwd $(ConvertTo-PowerShellSingleQuotedArgument $Cwd) $(ConvertTo-PowerShellSingleQuotedArgument $taskText)"
} else {
    ""
}
$providerFallbackPolicy = [ordered]@{
    Provider = "chatgpt"
    Firm = $providerFirm
    CodexFallbackAllowed = $codexFallbackAllowed
    ProviderReadyTimeoutSeconds = $providerReadyTimeoutSeconds
    CodexFallbackCommand = $codexFallbackCommand
    Reason = if ($providerFirm) {
        "Provider route is firm because ChatGPT was explicitly forced or provider fallback was disabled."
    } else {
        "Provider route is soft; if ChatGPT is not ready quickly, continue in Codex."
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
    ProviderFallbackPolicy = $providerFallbackPolicy
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
    providerFallbackPolicy = $providerFallbackPolicy
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
        Cwd = $Cwd
        ProviderReadyTimeoutSeconds = $providerReadyTimeoutSeconds
    }
    if ($providerFirm) { $chatGptParams.FirmProvider = $true } else { $chatGptParams.AllowProviderFallback = $true }
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
        Cwd = $Cwd
        ProviderReadyTimeoutSeconds = $providerReadyTimeoutSeconds
    }
    if ($providerFirm) { $chatGptParams.FirmProvider = $true } else { $chatGptParams.AllowProviderFallback = $true }
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
