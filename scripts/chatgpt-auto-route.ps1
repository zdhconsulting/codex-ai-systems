param(
    [string] $Project = "General",
    [string] $OutDir = "",
    [string] $InputFile = "",
    [string] $SessionPath = "",
    [switch] $DryRun,
    [switch] $NoOpen,
    [switch] $PacketOnly,
    [switch] $ForceChatGPT,
    [switch] $ForceCodex,
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

function Write-BridgeEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    ($Event | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $eventsPath -Encoding UTF8
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
    if ($Result.OpenedChatGPT) { Write-Host "Opened ChatGPT: yes" }
    if ($Result.RunnerSnippet) {
        Write-Host ""
        Write-Host "Codex Desktop Chrome runner:"
        Write-Host $Result.RunnerSnippet
    }
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

$route = if ($ForceChatGPT) {
    Select-AiWorkRoute -Text $taskText -ForceChatGPT
} elseif ($ForceCodex) {
    Select-AiWorkRoute -Text $taskText -ForceCodex
} else {
    Select-AiWorkRoute -Text $taskText
}

$fallbackProfile = Select-CodexGear -Text $taskText
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
        Project = $Project
        AssetOutDir = $assetOutDir
        CodexFallbackProfile = $fallbackProfile
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
    Start-Process "https://chatgpt.com/"
}

$runnerUri = "file:///" + (($runnerPath -replace '\\', '/') -replace ' ', '%20')
$runnerSnippet = "const { runChatGptChromeBridge } = await import(`"$runnerUri`"); await runChatGptChromeBridge({ promptPath: $(ConvertTo-JsString $promptPath), responsePath: $(ConvertTo-JsString $responsePath), project: $(ConvertTo-JsString $Project), outputDir: $(ConvertTo-JsString $assetOutDir), sessionPath: $(ConvertTo-JsString $sessionJsonPath) });"

$session = [ordered]@{
    SessionId = $sessionId
    Status = "prepared"
    CreatedAt = (Get-Date).ToString("o")
    Project = $Project
    Task = $taskText
    Route = $route
    CodexFallbackProfile = $fallbackProfile
    PromptPath = $promptPath
    ResponsePath = $responsePath
    AssetOutDir = $assetOutDir
    SessionPath = $sessionJsonPath
    RouteOutput = $routeOutput
    OpenedChatGPT = (-not $NoOpen)
    RunnerSnippet = $runnerSnippet
    SavingsLog = [ordered]@{
        AvoidedCodexCreativeWork = $true
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
    Route = $route.Route
    Confidence = $route.Confidence
    Signals = $route.Signals
    CodexFallbackProfile = $fallbackProfile
    PromptPath = $promptPath
    SessionPath = $sessionJsonPath
    AssetOutDir = $assetOutDir
})

$result = [pscustomobject]@{
    Status = "prepared"
    Route = $route
    Project = $Project
    PromptPath = $promptPath
    ResponsePath = $responsePath
    AssetOutDir = $assetOutDir
    SessionPath = $sessionJsonPath
    OpenedChatGPT = (-not $NoOpen)
    RunnerSnippet = $runnerSnippet
}
Write-BridgeResult -Result $result -AsJson:$Json
