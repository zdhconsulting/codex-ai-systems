param(
    [string]$OutputPath = (Join-Path $env:USERPROFILE ".codex\state\active-work-registry.json"),
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Ensure-ParentDir {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Text
    )
    Ensure-ParentDir -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-FileAgeHours {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return [math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalHours, 2)
    } catch {
        return $null
    }
}

function Get-ActiveAutomationFiles {
    param([string]$AutomationRoot)
    if (-not (Test-Path -LiteralPath $AutomationRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $AutomationRoot -Recurse -Filter automation.toml -ErrorAction SilentlyContinue | ForEach-Object {
        $raw = Get-Content -LiteralPath $_.FullName -Raw
        $status = if ($raw -match '(?m)^status\s*=\s*"([^"]+)"') { $Matches[1] } else { "UNKNOWN" }
        $name = if ($raw -match '(?m)^name\s*=\s*"([^"]+)"') { $Matches[1] } else { $_.Directory.Name }
        $id = if ($raw -match '(?m)^id\s*=\s*"([^"]+)"') { $Matches[1] } else { $_.Directory.Name }
        if ($status -eq "ACTIVE") {
            [pscustomobject]@{
                id = $id
                name = $name
                path = $_.FullName
                updated_at = $_.LastWriteTime.ToString("o")
            }
        }
    })
}

$codexHome = Join-Path $env:USERPROFILE ".codex"
$automationRoot = Join-Path $codexHome "automations"
$commandCenterRoot = Join-Path $env:USERPROFILE "OneDrive\Documents\New project 2\data\command-center"
$laneLeasesPath = Join-Path $commandCenterRoot "lane-leases.json"
$commandInboxPath = Join-Path $commandCenterRoot "command-inbox.json"
$backlogPath = Join-Path $codexHome "backlog\ai-manager-always-on-backlog.md"

$activeAutomations = @(Get-ActiveAutomationFiles -AutomationRoot $automationRoot)
$laneLeaseAgeHours = Get-FileAgeHours -Path $laneLeasesPath
$commandInboxAgeHours = Get-FileAgeHours -Path $commandInboxPath
$backlogAgeHours = Get-FileAgeHours -Path $backlogPath

$issues = @()
if ($null -eq $laneLeaseAgeHours) {
    $issues += "lane_leases_missing"
} elseif ($laneLeaseAgeHours -gt 24) {
    $issues += "lane_leases_stale_h=$laneLeaseAgeHours"
}
if ($null -eq $commandInboxAgeHours) {
    $issues += "command_inbox_missing"
} elseif ($commandInboxAgeHours -gt 24) {
    $issues += "command_inbox_stale_h=$commandInboxAgeHours"
}
if ($activeAutomations.Count -eq 0) {
    $issues += "no_active_automations"
}

$activeItems = @()
foreach ($automation in $activeAutomations) {
    $activeItems += [pscustomobject]@{
        type = "automation"
        id = $automation.id
        name = $automation.name
        owner_lane = "automation"
        proof_path = $automation.path
        resume_mode = "scheduler"
    }
}

$payload = [pscustomobject][ordered]@{
    generated_at = (Get-Date).ToString("o")
    source = "codex-active-work-registry"
    status = if ($issues.Count -eq 0) { "healthy" } else { "attention" }
    active_count = @($activeItems).Count
    active_items = $activeItems
    issues = $issues
    sources = [ordered]@{
        backlog_path = $backlogPath
        backlog_age_h = $backlogAgeHours
        lane_leases_path = $laneLeasesPath
        lane_leases_age_h = $laneLeaseAgeHours
        command_inbox_path = $commandInboxPath
        command_inbox_age_h = $commandInboxAgeHours
        automation_root = $automationRoot
        active_automation_count = @($activeAutomations).Count
    }
    note = "This registry proves what can actually resume without Zev. A running Desktop process alone is not movement."
}

Write-Utf8NoBomFile -Path $OutputPath -Text (($payload | ConvertTo-Json -Depth 8))
if (-not $Quiet) {
    $payload | ConvertTo-Json -Depth 8
}
