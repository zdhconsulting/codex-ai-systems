param(
    [string] $Project = "General",
    [string] $OutDir = "",
    [string] $Cwd = (Get-Location).Path,
    [string] $InputFile = "",
    [string] $SessionPath = "",
    [int] $ProviderReadyTimeoutSeconds = 30,
    [switch] $DryRun,
    [switch] $NoOpen,
    [switch] $PacketOnly,
    [switch] $ForceChatGPT,
    [switch] $ForceCodex,
    [switch] $AllowProviderFallback,
    [switch] $FirmProvider,
    [switch] $RequirePacket,
    [switch] $Json,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Task
)

$ErrorActionPreference = "Stop"
$codexHome = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
$routeScript = Join-Path $PSScriptRoot "chatgpt-route.ps1"
$returnScript = Join-Path $PSScriptRoot "chatgpt-return.ps1"
$runnerPath = Join-Path $PSScriptRoot "chatgpt-chrome-bridge.mjs"
$logRoot = Join-Path $codexHome "logs\chatgpt-bridge"
$eventsPath = Join-Path $logRoot "events.jsonl"

function ConvertTo-SafeName {
    param([string] $Value)
    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "General" }
    return $safe
}

function ConvertTo-JsString {
    param([string] $Value)
    return ($Value -replace '\\', '/') | ConvertTo-Json -Compress
}

function ConvertTo-PowerShellSingleQuotedArgument {
    param([string] $Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Write-BridgeEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $line = $Event | ConvertTo-Json -Compress -Depth 8
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $line | Add-Content -LiteralPath $eventsPath -Encoding UTF8
            return
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
    Write-Warning "Could not append ChatGPT bridge event after retries: $eventsPath"
}

function Write-BridgeResult {
    param(
        [object] $Result,
        [switch] $AsJson
    )
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 8
        return
    }

    Write-Host "ChatGPT auto bridge"
    Write-Host "Status: $($Result.Status)"
    if ($Result.Route) {
        Write-Host "Route: $($Result.Route.Route)"
        Write-Host "Reason: $($Result.Route.Reason)"
        Write-Host "Confidence: $($Result.Route.Confidence)"
        if ($Result.Route.Signals) {
            Write-Host "Signals: $($Result.Route.Signals -join ', ')"
        }
    }
    if ($Result.SessionPath) { Write-Host "Session: $($Result.SessionPath)" }
    if ($Result.PromptPath) { Write-Host "Prompt: $($Result.PromptPath)" }
    if ($Result.ResponsePath) { Write-Host "Response: $($Result.ResponsePath)" }
    if ($Result.HandoffPath) { Write-Host "Handoff: $($Result.HandoffPath)" }
    if ($Result.AssetOutDir) { Write-Host "Assets: $($Result.AssetOutDir)" }
    if ($Result.TaskKey) { Write-Host "Task key: $($Result.TaskKey)" }
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
    if ($Result.OpenedChatGPT) { Write-Host "Opened ChatGPT: yes" }
    if ($Result.RunnerSnippet) {
        Write-Host ""
        Write-Host "Codex Desktop Chrome runner:"
        Write-Host $Result.RunnerSnippet
    }
    if ($Result.ResumeSnippet) {
        Write-Host ""
        Write-Host "If ChatGPT is still generating, harvest later with:"
        Write-Host $Result.ResumeSnippet
    }
}

function Open-UrlInChrome {
    param([string] $Url)
    $chromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $chromeCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            Start-Process -FilePath $candidate -ArgumentList $Url | Out-Null
            return $true
        }
    }
    Start-Process $Url
    return $false
}

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing CodexGear module: $modulePath"
}
Import-Module $modulePath -Force

$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()
$safeProject = ConvertTo-SafeName $Project

if ($InputFile) {
    $returnArgs = @("-InputFile", $InputFile, "-Project", $Project, "-Json")
    if ($RequirePacket) { $returnArgs += "-RequirePacket" }
    $returnJson = (& $returnScript @returnArgs 2>&1 | Out-String).Trim()
    $returnResult = $returnJson | ConvertFrom-Json

    if ($SessionPath -and (Test-Path -LiteralPath $SessionPath)) {
        $session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
        $session | Add-Member -NotePropertyName Status -NotePropertyValue "imported" -Force
        $session | Add-Member -NotePropertyName ImportedAt -NotePropertyValue (Get-Date).ToString("o") -Force
        $session | Add-Member -NotePropertyName HandoffPath -NotePropertyValue $returnResult.Saved -Force
        $session | Add-Member -NotePropertyName HasPacket -NotePropertyValue $returnResult.HasPacket -Force
        $session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    }

    $event = [ordered]@{
        Type = "import"
        At = (Get-Date).ToString("o")
        Project = $Project
        InputFile = $InputFile
        SessionPath = $SessionPath
        HandoffPath = $returnResult.Saved
        HasPacket = $returnResult.HasPacket
    }
    Write-BridgeEvent $event

    $result = [pscustomobject]@{
        Status = "imported"
        ResponsePath = $InputFile
        HandoffPath = $returnResult.Saved
        HasPacket = $returnResult.HasPacket
        SessionPath = $SessionPath
    }
    Write-BridgeResult -Result $result -AsJson:$Json
    exit 0
}

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: chatgpt-auto-route.cmd [-Project NAME] [-OutDir DIR] `"TASK`""
    Write-Host "Use this for ChatGPT-routed writing, strategy, brainstorming, and ChatGPT-native image/logo generation."
    exit 1
}

$firmProviderTag = $taskText.ToLowerInvariant() -match "\[(firm-provider|provider-required|no-provider-fallback|strict-provider)\]" -or
    $taskText.ToLowerInvariant() -match "\s--(firm-provider|provider-required|no-provider-fallback|strict-provider)\b"
$forceChatGptTag = $taskText.ToLowerInvariant() -match "\[(chatgpt|gpt|force-chatgpt)\]" -or
    $taskText.ToLowerInvariant() -match "\s--(chatgpt|gpt|force-chatgpt)\b"
$providerReadyTimeoutSeconds = [Math]::Max(5, $ProviderReadyTimeoutSeconds)
$providerFirm = [bool]($FirmProvider -or $firmProviderTag -or $forceChatGptTag -or -not $AllowProviderFallback)
$codexFallbackAllowed = -not $providerFirm
$codexAutoCmd = Join-Path $PSScriptRoot "codex-auto.cmd"
$codexFallbackCommand = if ($codexFallbackAllowed) {
    "& $(ConvertTo-PowerShellSingleQuotedArgument $codexAutoCmd) -ForceCodex -NoOptimizeCredits -Cwd $(ConvertTo-PowerShellSingleQuotedArgument $Cwd) $(ConvertTo-PowerShellSingleQuotedArgument $taskText)"
} else {
    ""
}
$fallbackReason = if ($providerFirm -and $forceChatGptTag) {
    "Provider route is firm because ChatGPT was explicitly tagged."
} elseif ($providerFirm) {
    "Provider route is firm because ChatGPT was directly requested or provider fallback was disabled."
} else {
    "Provider route is soft; if ChatGPT is not ready quickly, continue in Codex."
}
$fallbackNextAction = if ($codexFallbackAllowed) {
    "If ChatGPT is unavailable after $providerReadyTimeoutSeconds seconds, run the fallback command and continue in Codex."
} else {
    "Fix or retry the ChatGPT bridge/provider lane; do not continue in Codex silently."
}
$providerFallbackPolicy = [ordered]@{
    Provider = "chatgpt"
    Firm = $providerFirm
    ProviderFirm = $providerFirm
    CodexFallbackAllowed = $codexFallbackAllowed
    ProviderReadyTimeoutSeconds = $providerReadyTimeoutSeconds
    CodexFallbackCommand = $codexFallbackCommand
    FallbackCommand = $codexFallbackCommand
    Reason = $fallbackReason
    FallbackReason = $fallbackReason
    FallbackNextAction = $fallbackNextAction
}

$route = if ($ForceChatGPT -or $forceChatGptTag) {
    Select-AiWorkRoute -Text $taskText -ForceChatGPT
} elseif ($ForceCodex) {
    Select-AiWorkRoute -Text $taskText -ForceCodex
} else {
    Select-AiWorkRoute -Text $taskText
}
if ($ForceChatGPT -and $AllowProviderFallback -and -not $forceChatGptTag) {
    $signals = @($route.Signals) | Where-Object { $_ }
    if ($signals.Count -eq 0) { $signals = @("gateway-selected ChatGPT route") }
    $route = [pscustomobject]@{
        Route = "chatgpt"
        Reason = "Gateway-selected ChatGPT route with soft Codex fallback."
        Confidence = if ($route.Confidence) { $route.Confidence } else { "high" }
        Signals = $signals
    }
}

$fallbackProfile = Select-CodexGear -Text $taskText
$taskKey = Get-ChatGatewayTaskKey -Text $taskText -Project $Project
$savingsEstimate = Get-ChatGatewaySavingsEstimate `
    -Text $taskText `
    -Route $route.Route `
    -ChatGPTSignals $route.Signals `
    -CodexFallbackProfile $fallbackProfile
$codexUsageBefore = Get-CodexLatestTokenSnapshot -CodexHome $codexHome
$assetOutDir = if ($OutDir) {
    $OutDir
} else {
    Join-Path $codexHome "generated_assets\chatgpt-bridge\$safeProject"
}

if ($DryRun -or $route.Route -ne "chatgpt") {
    $dryResult = [pscustomobject]@{
        Status = if ($DryRun) { "dry-run" } else { "not-routed" }
        Route = $route
        Task = $taskText
        TaskKey = $taskKey
        Project = $Project
        Cwd = $Cwd
        AssetOutDir = $assetOutDir
        ProviderFallbackPolicy = $providerFallbackPolicy
        CodexFallbackProfile = $fallbackProfile
        SavingsEstimate = $savingsEstimate
        CodexUsageBefore = $codexUsageBefore
        WouldOpenChatGPT = (-not $NoOpen -and $route.Route -eq "chatgpt")
        Note = if ($route.Route -ne "chatgpt") { "This task should stay in Codex unless forced with -ForceChatGPT." } else { "Dry run only. No prompt/session was created." }
    }
    Write-BridgeResult -Result $dryResult -AsJson:$Json
    if ($route.Route -ne "chatgpt" -and -not $DryRun) { exit 3 }
    exit 0
}

$sessionId = Get-Date -Format "yyyyMMdd-HHmmss"
$sessionDir = Join-Path $logRoot "$sessionId-$safeProject"
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
New-Item -ItemType Directory -Path $assetOutDir -Force | Out-Null

$promptPath = Join-Path $sessionDir "prompt.txt"
$responsePath = Join-Path $sessionDir "response.txt"
$sessionJsonPath = Join-Path $sessionDir "session.json"

$routeParams = @{
    NoOpen = $true
    Quiet = $true
    OutFile = $promptPath
}
if ($PacketOnly) { $routeParams.PacketOnly = $true }
$routeOutput = (& $routeScript @routeParams $taskText 2>&1 | Out-String).Trim()

if (-not $NoOpen) {
    Open-UrlInChrome "https://chatgpt.com/" | Out-Null
}

$providerReadyTimeoutMs = $providerReadyTimeoutSeconds * 1000
$fallbackAllowedJs = if ($codexFallbackAllowed) { "true" } else { "false" }
$providerFirmJs = if ($providerFirm) { "true" } else { "false" }
$runnerUri = "file:///" + (($runnerPath -replace '\\', '/') -replace ' ', '%20')
$runnerSnippet = "const { runChatGptChromeBridge } = await import(`"$runnerUri`"); await runChatGptChromeBridge({ promptPath: $(ConvertTo-JsString $promptPath), responsePath: $(ConvertTo-JsString $responsePath), project: $(ConvertTo-JsString $Project), outputDir: $(ConvertTo-JsString $assetOutDir), sessionPath: $(ConvertTo-JsString $sessionJsonPath), maxWaitMs: 95000, composerWaitMs: $providerReadyTimeoutMs, fallbackAllowed: $fallbackAllowedJs, providerFirm: $providerFirmJs, providerReadyTimeoutSeconds: $providerReadyTimeoutSeconds, codexFallbackCommand: $(ConvertTo-JsString $codexFallbackCommand) });"
$resumeSnippet = "const { resumeChatGptChromeBridge } = await import(`"$runnerUri`"); await resumeChatGptChromeBridge({ promptPath: $(ConvertTo-JsString $promptPath), responsePath: $(ConvertTo-JsString $responsePath), project: $(ConvertTo-JsString $Project), outputDir: $(ConvertTo-JsString $assetOutDir), sessionPath: $(ConvertTo-JsString $sessionJsonPath), maxWaitMs: 95000, composerWaitMs: $providerReadyTimeoutMs, fallbackAllowed: $fallbackAllowedJs, providerFirm: $providerFirmJs, providerReadyTimeoutSeconds: $providerReadyTimeoutSeconds, codexFallbackCommand: $(ConvertTo-JsString $codexFallbackCommand) });"

$session = [ordered]@{
    SessionId = $sessionId
    Status = "prepared"
    CreatedAt = (Get-Date).ToString("o")
    Project = $Project
    Cwd = $Cwd
    Task = $taskText
    TaskKey = $taskKey
    Route = $route
    ProviderFallbackPolicy = $providerFallbackPolicy
    CodexFallbackProfile = $fallbackProfile
    PromptPath = $promptPath
    ResponsePath = $responsePath
    AssetOutDir = $assetOutDir
    SessionPath = $sessionJsonPath
    RouteOutput = $routeOutput
    OpenedChatGPT = (-not $NoOpen)
    RunnerSnippet = $runnerSnippet
    ResumeSnippet = $resumeSnippet
    SavingsEstimate = $savingsEstimate
    CodexUsageBefore = $codexUsageBefore
    SavingsLog = [ordered]@{
        AvoidedCodexCreativeWork = $true
        EstimatedAvoidedCodexTokens = $savingsEstimate.EstimatedAvoidedCodexTokens
        EstimatedAvoidedCodexTurns = $savingsEstimate.AvoidedCodexTurns
        EstimateBasis = $savingsEstimate.Basis
        SavedCodexRole = "Codex only prepares, automates browser handoff, saves/imports assets, and verifies local results."
        RoutedWork = "ChatGPT handles detachable thinking or image generation."
    }
}
$session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sessionJsonPath -Encoding UTF8

Write-BridgeEvent ([ordered]@{
    Type = "prepared"
    At = (Get-Date).ToString("o")
    Project = $Project
    Task = $taskText
    TaskKey = $taskKey
    Route = $route.Route
    Confidence = $route.Confidence
    Signals = $route.Signals
    ProviderFallbackPolicy = $providerFallbackPolicy
    CodexFallbackProfile = $fallbackProfile
    PromptPath = $promptPath
    SessionPath = $sessionJsonPath
    AssetOutDir = $assetOutDir
    SavingsEstimate = $savingsEstimate
    CodexUsageBefore = $codexUsageBefore
})

$result = [pscustomobject]@{
    Status = "prepared"
    Route = $route
    Project = $Project
    Cwd = $Cwd
    PromptPath = $promptPath
    ResponsePath = $responsePath
    AssetOutDir = $assetOutDir
    SessionPath = $sessionJsonPath
    TaskKey = $taskKey
    ProviderFallbackPolicy = $providerFallbackPolicy
    SavingsEstimate = $savingsEstimate
    OpenedChatGPT = (-not $NoOpen)
    RunnerSnippet = $runnerSnippet
    ResumeSnippet = $resumeSnippet
}
Write-BridgeResult -Result $result -AsJson:$Json
