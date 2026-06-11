param(
    [string] $Project = "Gateway",
    [string] $Task = "",
    [string] $TaskKey = "",
    [string] $SessionPath = "",
    [ValidateRange(1, 5)]
    [int] $Rating = 3,
    [ValidateSet("good", "mixed", "bad", "unknown")]
    [string] $Outcome = "unknown",
    [string] $Notes = "",
    [string] $CodexHome = ""
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$modulePath = Join-Path $PSScriptRoot "CodexGear.psm1"
$eventsDir = Join-Path $CodexHome "logs\chatgpt-bridge"
$eventsPath = Join-Path $eventsDir "events.jsonl"

Import-Module $modulePath -Force

if ($SessionPath -and (Test-Path -LiteralPath $SessionPath)) {
    try {
        $session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
        if (-not $Task -and $session.Task) { $Task = $session.Task }
        if ((-not $TaskKey) -and $session.TaskKey) { $TaskKey = $session.TaskKey }
        if ($Project -eq "Gateway" -and $session.Project) { $Project = $session.Project }
    } catch {
        Write-Warning "Could not read session metadata: $($_.Exception.Message)"
    }
}

if (-not $TaskKey -and $Task) {
    $TaskKey = Get-ChatGatewayTaskKey -Text $Task -Project $Project
}

if (-not $TaskKey -and -not $Task) {
    Write-Error "Provide -Task, -TaskKey, or -SessionPath so feedback can be tied to a gateway run."
    exit 1
}

$feedback = [ordered]@{
    type = "gateway-feedback"
    at = (Get-Date).ToString("o")
    project = $Project
    task = $Task
    taskKey = $TaskKey
    sessionPath = $SessionPath
    rating = $Rating
    outcome = $Outcome
    notes = $Notes
}

New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
($feedback | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $eventsPath -Encoding UTF8

$cachePath = if ($TaskKey) { Join-Path $CodexHome "cache\chatgpt-bridge\$TaskKey.json" } else { "" }
$cacheUpdated = $false
if ($cachePath -and (Test-Path -LiteralPath $cachePath)) {
    try {
        $entry = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        $feedbackItems = @()
        if ($entry.Feedback) { $feedbackItems = @($entry.Feedback) }
        $feedbackItems += [pscustomobject]$feedback
        if ($feedbackItems.Count -gt 25) {
            $feedbackItems = $feedbackItems | Select-Object -Last 25
        }
        $entry | Add-Member -NotePropertyName Feedback -NotePropertyValue $feedbackItems -Force
        $entry | Add-Member -NotePropertyName LastFeedback -NotePropertyValue ([pscustomobject]$feedback) -Force
        $entry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cachePath -Encoding UTF8
        $cacheUpdated = $true
    } catch {
        Write-Warning "Feedback event was logged, but cache metadata was not updated: $($_.Exception.Message)"
    }
}

Write-Host "Gateway feedback logged."
Write-Host "Project: $Project"
if ($TaskKey) { Write-Host "Task key: $TaskKey" }
Write-Host "Rating: $Rating"
Write-Host "Outcome: $Outcome"
if ($Notes) { Write-Host "Notes: $Notes" }
Write-Host "Events: $eventsPath"
if ($cachePath) {
    Write-Host "Cache metadata: $(if ($cacheUpdated) { "updated" } else { "not found" })"
    Write-Host "Cache path: $cachePath"
}
