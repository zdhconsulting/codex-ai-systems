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
            CacheHits = 0
            EstimatedAvoidedCodexTokensFromDecisions = 0
            EstimatedAvoidedCodexTokensFromDispatches = 0
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

function Sum-Savings {
    param([object[]] $InputEvents)
    $sum = 0
    foreach ($event in $InputEvents) {
        $route = Get-EventValue -Event $event -Name "route"
        if ($route -ne "chatgpt" -and $route -ne "hybrid") { continue }
        $estimate = Get-EventValue -Event $event -Name "savingsEstimate"
        if ($estimate -and $estimate.EstimatedAvoidedCodexTokens) {
            $sum += [int]$estimate.EstimatedAvoidedCodexTokens
        }
    }
    return $sum
}

$decisionRows = @(
    $decisionEvents |
        Sort-Object { Get-EventValue -Event $_ -Name "at" } -Descending |
        ForEach-Object {
            $cache = Get-EventValue -Event $_ -Name "cache"
            $estimate = Get-EventValue -Event $_ -Name "savingsEstimate"
            [pscustomobject]@{
                At = Get-EventValue -Event $_ -Name "at"
                Project = Get-EventValue -Event $_ -Name "project"
                Route = Get-EventValue -Event $_ -Name "route"
                Confidence = Get-EventValue -Event $_ -Name "confidence"
                AskFirst = Get-EventValue -Event $_ -Name "askFirst"
                CacheStatus = if ($cache) { $cache.Status } else { "" }
                EstimatedAvoidedCodexTokens = if ($estimate -and $estimate.EstimatedAvoidedCodexTokens) { [int]$estimate.EstimatedAvoidedCodexTokens } else { 0 }
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
    CacheHits = $cacheHits.Count
    EstimatedAvoidedCodexTokensFromDecisions = Sum-Savings -InputEvents $decisionEvents
    EstimatedAvoidedCodexTokensFromDispatches = (Sum-Savings -InputEvents $gatewayChatGptDispatches) + (Sum-Savings -InputEvents $cacheHits)
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
Write-Host "  Cache hits: $($summary.CacheHits)"
Write-Host ""
Write-Host "Savings estimates"
Write-Host "  From ChatGPT/hybrid decisions: $($summary.EstimatedAvoidedCodexTokensFromDecisions) Codex tokens"
Write-Host "  From actual dispatch/cache events: $($summary.EstimatedAvoidedCodexTokensFromDispatches) Codex tokens"
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
