param(
    [string] $CodexHome = "",
    [string] $Project = "",
    [string] $Route = "",
    [int] $SinceDays = 30,
    [int] $Limit = 25,
    [switch] $All,
    [switch] $IncludeTestProjects,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$eventsPath = Join-Path $CodexHome "logs\chatgpt-bridge\events.jsonl"
$modulePath = Join-Path $CodexHome "scripts\CodexGear.psm1"
if (Test-Path -LiteralPath $modulePath) {
    Import-Module $modulePath -Force
}

function Get-EventValue {
    param(
        [object] $Event,
        [string] $Name
    )

    $property = $Event.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}

function ConvertTo-ShortText {
    param(
        [string] $Text,
        [int] $Max = 110
    )

    $clean = (($Text -replace "\s+", " ").Trim())
    if ($clean.Length -le $Max) { return $clean }
    return ($clean.Substring(0, $Max - 3) + "...")
}

function ConvertTo-StringList {
    param([object] $Value)
    if ($null -eq $Value) { return "" }
    return ((@($Value) | Where-Object { $_ } | ForEach-Object { "$_" }) -join ", ")
}

function Get-EventSavingsEstimate {
    param([object] $Event)

    $route = Get-EventValue -Event $Event -Name "route"
    if ($route -ne "chatgpt" -and $route -ne "hybrid") { return 0 }

    $estimate = Get-EventValue -Event $Event -Name "savingsEstimate"
    if ($estimate -and $estimate.EstimatedAvoidedCodexTokens -and [int]$estimate.EstimatedAvoidedCodexTokens -gt 0) {
        return [int]$estimate.EstimatedAvoidedCodexTokens
    }

    if (-not (Get-Command Get-ChatGatewaySavingsEstimate -ErrorAction SilentlyContinue)) {
        return 0
    }

    $task = Get-EventValue -Event $Event -Name "task"
    $signals = Get-EventValue -Event $Event -Name "chatgptSignals"
    if (-not $signals) { $signals = Get-EventValue -Event $Event -Name "Signals" }
    $fallback = Get-EventValue -Event $Event -Name "codexFallbackProfile"
    if (-not $fallback) { $fallback = Get-EventValue -Event $Event -Name "CodexFallbackProfile" }
    if (-not $fallback) { $fallback = "fast" }

    $backfill = Get-ChatGatewaySavingsEstimate -Text "$task" -Route "$route" -ChatGPTSignals @($signals) -CodexFallbackProfile "$fallback"
    return [int]$backfill.EstimatedAvoidedCodexTokens
}

function Get-SessionSavingsEstimate {
    param([object] $Session)

    if (-not $Session) { return 0 }
    if (-not (Get-Command Get-ChatGatewaySavingsEstimate -ErrorAction SilentlyContinue)) {
        return 0
    }

    $route = "chatgpt"
    $signals = @()
    if ($Session.Route) {
        if ($Session.Route.Route) { $route = $Session.Route.Route }
        if ($Session.Route.Signals) { $signals = @($Session.Route.Signals) }
    }
    $fallback = if ($Session.CodexFallbackProfile) { $Session.CodexFallbackProfile } else { "fast" }
    $task = if ($Session.Task) { "$($Session.Task)" } else { "" }
    if ([string]::IsNullOrWhiteSpace($task)) { return 0 }
    $estimate = Get-ChatGatewaySavingsEstimate -Text "$task" -Route "$route" -ChatGPTSignals $signals -CodexFallbackProfile "$fallback"
    return [int]$estimate.EstimatedAvoidedCodexTokens
}

function Get-BridgePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    return ($Path -replace "/", "\")
}

if (-not (Test-Path -LiteralPath $eventsPath)) {
    $empty = [pscustomobject]@{
        Summary = [ordered]@{
            EventsPath = $eventsPath
            TotalEvents = 0
            TotalDecisions = 0
            ChatGPTDecisions = 0
            CodexDecisions = 0
            HybridDecisions = 0
            AskFirstDecisions = 0
            GatewayDispatchesToChatGPT = 0
            PreparedChatGPTSessions = 0
            CompletedChatGPTSessions = 0
            UniqueCompletedChatGPTSessions = 0
            CacheHits = 0
            EstimatedAvoidedCodexTokensFromDecisions = 0
            EstimatedAvoidedCodexTokensFromDispatches = 0
            EstimatedAvoidedCodexTokensFromPreparedSessions = 0
            EstimatedAvoidedCodexTokensFromUniqueCompletedSessions = 0
        }
        Decisions = @()
    }
    if ($Json) { $empty | ConvertTo-Json -Depth 8; exit 0 }
    Write-Host "ChatGPT bridge tally"
    Write-Host "Events file not found: $eventsPath"
    exit 0
}

$cutoff = if ($SinceDays -gt 0) { (Get-Date).AddDays(-1 * $SinceDays) } else { $null }
$testProjectPattern = "^(gear-test|gateway-test|gateway smoke)$"
$events = New-Object System.Collections.Generic.List[object]

foreach ($line in (Get-Content -LiteralPath $eventsPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $event = $line | ConvertFrom-Json
    } catch {
        continue
    }

    $atText = Get-EventValue -Event $event -Name "at"
    $at = $null
    if ($atText) {
        try { $at = [datetime]::Parse($atText) } catch { $at = $null }
    }
    if ($cutoff -and $at -and $at -lt $cutoff) { continue }

    $projectValue = (Get-EventValue -Event $event -Name "project")
    if ($Project -and $projectValue -notlike "*$Project*") { continue }
    if (-not $IncludeTestProjects -and $projectValue -and ($projectValue -match $testProjectPattern)) { continue }

    $routeValue = (Get-EventValue -Event $event -Name "route")
    if ($Route -and $routeValue -ne $Route) { continue }

    $events.Add($event) | Out-Null
}

$decisionEvents = @($events | Where-Object { (Get-EventValue -Event $_ -Name "type") -eq "gateway-classified" })
$chatGptDecisions = @($decisionEvents | Where-Object { (Get-EventValue -Event $_ -Name "route") -eq "chatgpt" })
$codexDecisions = @($decisionEvents | Where-Object { (Get-EventValue -Event $_ -Name "route") -eq "codex" })
$hybridDecisions = @($decisionEvents | Where-Object { (Get-EventValue -Event $_ -Name "route") -eq "hybrid" })
$askFirstDecisions = @($decisionEvents | Where-Object { [bool](Get-EventValue -Event $_ -Name "askFirst") })
$gatewayChatGptDispatches = @($events | Where-Object {
    (Get-EventValue -Event $_ -Name "type") -eq "gateway-dispatched" -and
    ((Get-EventValue -Event $_ -Name "route") -eq "chatgpt" -or (Get-EventValue -Event $_ -Name "route") -eq "hybrid")
})
$preparedChatGptSessions = @($events | Where-Object { (Get-EventValue -Event $_ -Name "type") -eq "prepared" -and (Get-EventValue -Event $_ -Name "Route") -eq "chatgpt" })
$completedChatGptSessions = @($events | Where-Object { (Get-EventValue -Event $_ -Name "type") -eq "complete" })
$cacheHits = @($events | Where-Object { (Get-EventValue -Event $_ -Name "type") -eq "gateway-cache-hit" })

$preparedBySessionPath = @{}
foreach ($event in $preparedChatGptSessions) {
    $preparedSessionPath = Get-BridgePath (Get-EventValue -Event $event -Name "SessionPath")
    if ($preparedSessionPath -and -not $preparedBySessionPath.ContainsKey($preparedSessionPath)) {
        $preparedBySessionPath[$preparedSessionPath] = $event
    }
}

$uniqueCompletedSessions = @{}
foreach ($event in $completedChatGptSessions) {
    $sessionPath = Get-BridgePath (Get-EventValue -Event $event -Name "sessionPath")
    $responsePath = Get-BridgePath (Get-EventValue -Event $event -Name "responsePath")
    if (-not $sessionPath -and $responsePath) {
        $responseDir = Split-Path -Parent $responsePath
        if ($responseDir) { $sessionPath = Join-Path $responseDir "session.json" }
    }
    $key = if ($sessionPath) { $sessionPath } elseif ($responsePath) { $responsePath } else { (Get-EventValue -Event $event -Name "at") }
    if (-not $uniqueCompletedSessions.ContainsKey($key)) {
        $session = $null
        if ($sessionPath -and (Test-Path -LiteralPath $sessionPath)) {
            try { $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json } catch { $session = $null }
        }
        $estimate = Get-SessionSavingsEstimate -Session $session
        if ($estimate -eq 0 -and $sessionPath -and $preparedBySessionPath.ContainsKey($sessionPath)) {
            $estimate = Get-EventSavingsEstimate -Event $preparedBySessionPath[$sessionPath]
        }
        $uniqueCompletedSessions[$key] = [pscustomobject]@{
            Key = $key
            Event = $event
            Session = $session
            Estimate = $estimate
        }
    }
}

function Sum-Savings {
    param([object[]] $InputEvents)
    $sum = 0
    foreach ($event in $InputEvents) {
        $route = Get-EventValue -Event $event -Name "route"
        if ($route -ne "chatgpt" -and $route -ne "hybrid") { continue }
        $sum += Get-EventSavingsEstimate -Event $event
    }
    return $sum
}

$decisionRows = @(
    $decisionEvents |
        Sort-Object { Get-EventValue -Event $_ -Name "at" } -Descending |
        ForEach-Object {
            $cache = Get-EventValue -Event $_ -Name "cache"
            [pscustomobject]@{
                At = Get-EventValue -Event $_ -Name "at"
                Project = Get-EventValue -Event $_ -Name "project"
                Route = Get-EventValue -Event $_ -Name "route"
                Confidence = Get-EventValue -Event $_ -Name "confidence"
                AskFirst = Get-EventValue -Event $_ -Name "askFirst"
                CacheStatus = if ($cache) { $cache.Status } else { "" }
                EstimatedAvoidedCodexTokens = Get-EventSavingsEstimate -Event $_
                Reason = Get-EventValue -Event $_ -Name "reason"
                ChatGPTSignals = ConvertTo-StringList (Get-EventValue -Event $_ -Name "chatgptSignals")
                CodexSignals = ConvertTo-StringList (Get-EventValue -Event $_ -Name "codexSignals")
                Task = Get-EventValue -Event $_ -Name "task"
                TaskKey = Get-EventValue -Event $_ -Name "taskKey"
            }
        }
)

if (-not $All -and $Limit -gt 0) {
    $decisionRows = @($decisionRows | Select-Object -First $Limit)
}

$summary = [ordered]@{
    EventsPath = $eventsPath
    SinceDays = $SinceDays
    ProjectFilter = $Project
    RouteFilter = $Route
    TestProjectsIncluded = [bool]$IncludeTestProjects
    TotalEvents = $events.Count
    TotalDecisions = $decisionEvents.Count
    ChatGPTDecisions = $chatGptDecisions.Count
    CodexDecisions = $codexDecisions.Count
    HybridDecisions = $hybridDecisions.Count
    AskFirstDecisions = $askFirstDecisions.Count
    GatewayDispatchesToChatGPT = $gatewayChatGptDispatches.Count
    PreparedChatGPTSessions = $preparedChatGptSessions.Count
    CompletedChatGPTSessions = $completedChatGptSessions.Count
    UniqueCompletedChatGPTSessions = $uniqueCompletedSessions.Count
    CacheHits = $cacheHits.Count
    EstimatedAvoidedCodexTokensFromDecisions = Sum-Savings -InputEvents $decisionEvents
    EstimatedAvoidedCodexTokensFromDispatches = (Sum-Savings -InputEvents $gatewayChatGptDispatches) + (Sum-Savings -InputEvents $cacheHits)
    EstimatedAvoidedCodexTokensFromPreparedSessions = Sum-Savings -InputEvents $preparedChatGptSessions
    EstimatedAvoidedCodexTokensFromUniqueCompletedSessions = [int](($uniqueCompletedSessions.Values | Measure-Object -Property Estimate -Sum).Sum)
}

$result = [pscustomobject]@{
    Summary = $summary
    Decisions = $decisionRows
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
    exit 0
}

Write-Host "ChatGPT bridge tally"
Write-Host "Events: $eventsPath"
Write-Host "Window: $(if ($SinceDays -gt 0) { "$SinceDays day(s)" } else { "all time" })"
if ($Project) { Write-Host "Project filter: $Project" }
if ($Route) { Write-Host "Route filter: $Route" }
Write-Host "Test projects included: $([bool]$IncludeTestProjects)"
Write-Host ""
Write-Host "Decisions"
Write-Host "  Total: $($summary.TotalDecisions)"
Write-Host "  ChatGPT: $($summary.ChatGPTDecisions)"
Write-Host "  Codex: $($summary.CodexDecisions)"
Write-Host "  Hybrid: $($summary.HybridDecisions)"
Write-Host "  Ask-first: $($summary.AskFirstDecisions)"
Write-Host ""
Write-Host "Moves / outcomes"
Write-Host "  Gateway dispatches to ChatGPT/hybrid: $($summary.GatewayDispatchesToChatGPT)"
Write-Host "  Prepared ChatGPT sessions: $($summary.PreparedChatGPTSessions)"
Write-Host "  Completed ChatGPT sessions: $($summary.CompletedChatGPTSessions)"
Write-Host "  Unique completed ChatGPT sessions: $($summary.UniqueCompletedChatGPTSessions)"
Write-Host "  Cache hits: $($summary.CacheHits)"
Write-Host ""
Write-Host "Savings estimates"
Write-Host "  From ChatGPT/hybrid decisions: $($summary.EstimatedAvoidedCodexTokensFromDecisions) Codex tokens"
Write-Host "  From actual dispatch/cache events: $($summary.EstimatedAvoidedCodexTokensFromDispatches) Codex tokens"
Write-Host "  From prepared ChatGPT sessions: $($summary.EstimatedAvoidedCodexTokensFromPreparedSessions) Codex tokens"
Write-Host "  From unique completed ChatGPT sessions: $($summary.EstimatedAvoidedCodexTokensFromUniqueCompletedSessions) Codex tokens"
Write-Host ""
Write-Host "Recent decisions"
foreach ($row in $decisionRows) {
    Write-Host ""
    Write-Host "$($row.At) | $($row.Project) | route=$($row.Route) | confidence=$($row.Confidence) | askFirst=$($row.AskFirst) | cache=$($row.CacheStatus) | estSaved=$($row.EstimatedAvoidedCodexTokens)"
    Write-Host "Task: $(ConvertTo-ShortText $row.Task)"
    Write-Host "Why: $(ConvertTo-ShortText $row.Reason 180)"
    if ($row.ChatGPTSignals) { Write-Host "ChatGPT signals: $($row.ChatGPTSignals)" }
    if ($row.CodexSignals) { Write-Host "Codex signals: $($row.CodexSignals)" }
}
