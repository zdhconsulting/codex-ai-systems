param(
    [string] $Project = "Provider Gateway",
    [string] $OutDir = "",
    [string] $Cwd = (Get-Location).Path,
    [int] $Limit = 1,
    [string] $BriefId = "",
    [string] $PromptPath = "",
    [switch] $DryRun,
    [switch] $Json,
    [switch] $ForceChatGPT,
    [switch] $ForceDeepSeek,
    [switch] $ForceCodex,
    [switch] $NoOpen,
    [switch] $NoCopy,
    [switch] $PacketOnly,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Task
)

$ErrorActionPreference = "Stop"
$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: ai-provider-gateway.cmd [-DryRun] [-ForceDeepSeek|-ForceChatGPT|-ForceCodex] [-Project NAME] `"TASK`""
    Write-Host "Routes work to codex, chatgpt, deepseek, or hybrid based on local-risk signals and provider strengths."
    exit 1
}

$codexHome = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
$chatGptGateway = Join-Path $PSScriptRoot "codex-gateway.ps1"
$deepSeekRoute = Join-Path $PSScriptRoot "deepseek-route.ps1"
$codexAuto = Join-Path $PSScriptRoot "codex-auto.ps1"
$eventsDir = Join-Path $codexHome "logs\chatgpt-bridge"
$eventsPath = Join-Path $eventsDir "events.jsonl"

Import-Module $modulePath -Force

function ConvertTo-SignalText {
    param([object[]] $Signals)
    if ($Signals -and $Signals.Count -gt 0) { return ($Signals -join ", ") }
    return "none"
}

function Write-GatewayEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
    ($Event | ConvertTo-Json -Compress -Depth 10) | Add-Content -LiteralPath $eventsPath -Encoding UTF8
}

function Write-ProviderResult {
    param(
        [object] $Result,
        [switch] $AsJson
    )
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 10
        return
    }

    Write-Host "AI provider gateway"
    Write-Host "Status: $($Result.Status)"
    Write-Host "Route: $($Result.Route)"
    Write-Host "Provider: $($Result.Provider)"
    Write-Host "Dispatch: $($Result.Dispatch)"
    Write-Host "Confidence: $($Result.Confidence)"
    Write-Host "Ask first: $($Result.AskFirst)"
    Write-Host "Reason: $($Result.Reason)"
    Write-Host "DeepSeek signals: $(ConvertTo-SignalText $Result.DeepSeekSignals)"
    Write-Host "ChatGPT signals: $(ConvertTo-SignalText $Result.ChatGPTSignals)"
    Write-Host "Codex signals: $(ConvertTo-SignalText $Result.CodexSignals)"
    Write-Host "Next action: $($Result.NextAction)"
    if ($Result.SavingsEstimate) {
        Write-Host "Savings estimate: $($Result.SavingsEstimate.EstimatedAvoidedCodexTokens) Codex tokens / $($Result.SavingsEstimate.AvoidedCodexTurns) turn(s) avoided ($($Result.SavingsEstimate.Basis))"
    }
    if ($Result.CodexUsageBefore -and $null -ne $Result.CodexUsageBefore.PrimaryUsedPercent) {
        Write-Host "Codex usage before: primary $($Result.CodexUsageBefore.PrimaryUsedPercent)% / secondary $($Result.CodexUsageBefore.SecondaryUsedPercent)%"
    }
    if ($Result.ExitCode -ne $null) {
        Write-Host "Dispatch exit code: $($Result.ExitCode)"
    }
}

function Test-MrSeoDeepSeekHook {
    param(
        [string] $Cwd,
        [string] $Project,
        [string] $Task
    )
    $isMrSeo = ($Cwd -match '(?i)Mr\.SEO$|Mr\.SEO\\|Mr\.SEO/') -or ($Project -match '(?i)mr\.?seo|mr seo')
    $isWriterTask = $Task -match '(?i)\b(deepseek|writer|article|article desk|seo content|content draft|writer packet|brief)\b'
    $script = Join-Path $Cwd "scripts\dispatch_deepseek_writer_packets.py"
    return ($isMrSeo -and $isWriterTask -and (Test-Path -LiteralPath $script))
}

$route = Select-AiProviderRoute -Text $taskText -Project $Project -Cwd $Cwd -ForceChatGPT:$ForceChatGPT -ForceDeepSeek:$ForceDeepSeek -ForceCodex:$ForceCodex
$fallbackProfile = Select-CodexGear -Text $taskText
$taskKey = Get-ChatGatewayTaskKey -Text $taskText -Project $Project
$selectedSignals = if ($route.Route -eq "deepseek") { $route.DeepSeekSignals } else { $route.ChatGPTSignals }
$savingsEstimate = Get-ChatGatewaySavingsEstimate -Text $taskText -Route $route.Route -ChatGPTSignals $selectedSignals -CodexFallbackProfile $fallbackProfile
$codexUsageBefore = Get-CodexLatestTokenSnapshot -CodexHome $codexHome

$result = [ordered]@{
    Status = if ($DryRun) { "dry-run" } else { "classified" }
    Route = $route.Route
    Provider = $route.Provider
    Dispatch = $route.Dispatch
    Confidence = $route.Confidence
    AskFirst = $route.AskFirst
    Reason = $route.Reason
    NextAction = $route.NextAction
    DeepSeekSignals = $route.DeepSeekSignals
    ChatGPTSignals = $route.ChatGPTSignals
    CodexSignals = $route.CodexSignals
    CodexFallbackProfile = $fallbackProfile
    Project = $Project
    Cwd = $Cwd
    Task = $taskText
    TaskKey = $taskKey
    SavingsEstimate = $savingsEstimate
    CodexUsageBefore = $codexUsageBefore
}

Write-GatewayEvent ([ordered]@{
    type = "gateway-classified"
    at = (Get-Date).ToString("o")
    gateway = "ai-provider"
    project = $Project
    cwd = $Cwd
    task = $taskText
    taskKey = $taskKey
    route = $route.Route
    provider = $route.Provider
    dispatch = $route.Dispatch
    confidence = $route.Confidence
    askFirst = $route.AskFirst
    reason = $route.Reason
    deepseekSignals = $route.DeepSeekSignals
    chatgptSignals = $route.ChatGPTSignals
    codexSignals = $route.CodexSignals
    codexFallbackProfile = $fallbackProfile
    savingsEstimate = $savingsEstimate
    codexUsageBefore = $codexUsageBefore
})

if ($DryRun) {
    Write-ProviderResult -Result ([pscustomobject]$result) -AsJson:$Json
    exit 0
}

if ($route.Route -eq "hybrid") {
    $result["Status"] = "ask-first"
    Write-GatewayEvent ([ordered]@{
        type = "gateway-ask-first"
        at = (Get-Date).ToString("o")
        gateway = "ai-provider"
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "hybrid"
        provider = $route.Provider
        reason = $route.Reason
    })
    Write-ProviderResult -Result ([pscustomobject]$result) -AsJson:$Json
    exit 0
}

if ($route.Route -eq "chatgpt") {
    $params = @{
        Project = $Project
        ForceChatGPT = $true
        Cwd = $Cwd
    }
    if ($OutDir) { $params.OutDir = $OutDir }
    if ($NoOpen) { $params.NoOpen = $true }
    if ($PacketOnly) { $params.PacketOnly = $true }
    & $chatGptGateway @params $taskText
    $exitCode = if ($?) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
    $result["Status"] = "dispatched"
    $result["ExitCode"] = $exitCode
    Write-GatewayEvent ([ordered]@{
        type = "gateway-dispatched"
        at = (Get-Date).ToString("o")
        gateway = "ai-provider"
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "chatgpt"
        provider = "chatgpt"
        dispatch = "codex-gateway"
        exitCode = $exitCode
        avoidedCodexCreativeWork = $true
        savingsEstimate = $savingsEstimate
    })
    exit $exitCode
}

if ($route.Route -eq "deepseek") {
    if (Test-MrSeoDeepSeekHook -Cwd $Cwd -Project $Project -Task $taskText) {
        $args = @("scripts/dispatch_deepseek_writer_packets.py", "--limit", "$Limit")
        if ($BriefId) { $args += @("--brief-id", $BriefId) }
        if ($PromptPath) { $args += @("--prompt-path", $PromptPath) }
        if (-not $NoOpen) { $args += "--open" }
        if (-not $NoCopy) { $args += "--copy-prompt" }
        Push-Location -LiteralPath $Cwd
        try {
            & python @args
            $exitCode = if ($?) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
        } finally {
            Pop-Location
        }
        $result["Status"] = "dispatched"
        $result["Dispatch"] = "mrseo-deepseek-writer"
        $result["ExitCode"] = $exitCode
        Write-GatewayEvent ([ordered]@{
            type = "gateway-dispatched"
            at = (Get-Date).ToString("o")
            gateway = "ai-provider"
            project = $Project
            task = $taskText
            taskKey = $taskKey
            route = "deepseek"
            provider = "deepseek"
            dispatch = "mrseo-deepseek-writer"
            exitCode = $exitCode
            avoidedCodexCreativeWork = $true
            savingsEstimate = $savingsEstimate
        })
        exit $exitCode
    }

    $params = @{
        Project = $Project
    }
    if ($NoOpen) { $params.NoOpen = $true }
    if ($NoCopy) { $params.NoCopy = $true }
    if ($PacketOnly) { $params.PacketOnly = $true }
    & $deepSeekRoute @params $taskText
    $exitCode = if ($?) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
    $result["Status"] = "dispatched"
    $result["ExitCode"] = $exitCode
    Write-GatewayEvent ([ordered]@{
        type = "gateway-dispatched"
        at = (Get-Date).ToString("o")
        gateway = "ai-provider"
        project = $Project
        task = $taskText
        taskKey = $taskKey
        route = "deepseek"
        provider = "deepseek"
        dispatch = "deepseek-route"
        exitCode = $exitCode
        avoidedCodexCreativeWork = $true
        savingsEstimate = $savingsEstimate
    })
    exit $exitCode
}

$codexArgs = @("-NoOptimizeCredits", "-Cwd", $Cwd)
if ($ForceCodex) { $codexArgs += "-ForceCodex" }
$codexArgs += $taskText
& $codexAuto @codexArgs
$codexExitCode = if ($?) { 0 } elseif ($global:LASTEXITCODE -is [int]) { [int]$global:LASTEXITCODE } else { 1 }
$result["Status"] = "dispatched"
$result["ExitCode"] = $codexExitCode
Write-GatewayEvent ([ordered]@{
    type = "gateway-dispatched"
    at = (Get-Date).ToString("o")
    gateway = "ai-provider"
    project = $Project
    cwd = $Cwd
    task = $taskText
    taskKey = $taskKey
    route = "codex"
    provider = "codex"
    dispatch = "codex-auto"
    exitCode = $codexExitCode
    avoidedCodexCreativeWork = $false
    savingsEstimate = $savingsEstimate
})
exit $codexExitCode
