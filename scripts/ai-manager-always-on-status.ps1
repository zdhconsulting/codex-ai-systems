param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$EmitJson
)

$ErrorActionPreference = "Stop"

function Has-Text {
    param([object]$Value)
    return ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value))
}

function Get-GitStatus {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
        return [pscustomobject]@{
            is_repo = $false
            dirty_count = $null
            branch = $null
            remote = $null
        }
    }

    $status = & git -C $Root status --short 2>$null
    $branch = & git -C $Root rev-parse --abbrev-ref HEAD 2>$null
    $remote = & git -C $Root remote get-url origin 2>$null

    return [pscustomobject]@{
        is_repo = $true
        dirty_count = @($status).Count
        branch = if (Has-Text $branch) { [string]$branch } else { $null }
        remote = if (Has-Text $remote) { [string]$remote } else { $null }
    }
}

function Read-OptionalJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-RecentTimestamp {
    param(
        [object]$Value,
        [int]$MaxAgeMinutes = 3
    )
    if (-not (Has-Text $Value)) { return $false }
    try {
        $timestamp = [datetimeoffset]::Parse([string]$Value)
        return ([datetimeoffset](Get-Date) - $timestamp).TotalMinutes -le $MaxAgeMinutes
    } catch {
        return $false
    }
}

function Test-RecentFile {
    param(
        [string]$Path,
        [int]$MaxAgeHours = 12
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        return (((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalHours -le $MaxAgeHours)
    } catch {
        return $false
    }
}

function Get-FileDetail {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "missing: $Path" }
    $item = Get-Item -LiteralPath $Path
    $ageHours = [math]::Round(((Get-Date) - $item.LastWriteTime).TotalHours, 2)
    return "age_h=$ageHours; path=$Path"
}

$codexHome = Join-Path $env:USERPROFILE ".codex"
$backlogPath = Join-Path $codexHome "backlog\ai-manager-always-on-backlog.md"
$ownerButtonPath = Join-Path $codexHome "scripts\owner-button.cmd"
$shellStewardScript = Join-Path $codexHome "scripts\codex-shell-steward.ps1"
$shellStewardStatePath = Join-Path $codexHome "tmp\codex-shell-steward-state.json"
$automationRoot = Join-Path $codexHome "automations"
$activeWorkRegistryPath = Join-Path $codexHome "state\active-work-registry.json"
$commandCenterRoot = Join-Path $env:USERPROFILE "OneDrive\Documents\New project 2\data\command-center"
$laneLeasesPath = Join-Path $commandCenterRoot "lane-leases.json"
$commandInboxPath = Join-Path $commandCenterRoot "command-inbox.json"

$automationFiles = @()
if (Test-Path -LiteralPath $automationRoot) {
    $automationFiles = @(Get-ChildItem -Path $automationRoot -Recurse -Filter automation.toml -ErrorAction SilentlyContinue)
}

$shellStewardState = Read-OptionalJson -Path $shellStewardStatePath
$shellStewardStateHealthy = (
    $null -ne $shellStewardState -and
    [string]$shellStewardState.status -in @("healthy", "already_running", "cooldown", "healing") -and
    (Test-RecentTimestamp -Value $shellStewardState.updated_at -MaxAgeMinutes 3)
)

$shellStewardProcesses = @()
if (-not $shellStewardStateHealthy) {
    $shellStewardProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { ([string]$_.Path) -like "*powershell*" -or ([string]$_.Path) -like "*pwsh*" } catch { $false }
    } | Where-Object {
        try { ([string]$_.MainWindowTitle) -like "*codex-shell-steward*" } catch { $false }
    })
}

$gitStatus = Get-GitStatus -Root $ProjectRoot
$now = [datetimeoffset](Get-Date)
$checks = @(
    [pscustomobject]@{ name = "backlog_present"; ok = (Test-Path -LiteralPath $backlogPath); detail = $backlogPath },
    [pscustomobject]@{ name = "owner_button_tool_present"; ok = (Test-Path -LiteralPath $ownerButtonPath); detail = $ownerButtonPath },
    [pscustomobject]@{ name = "shell_steward_script_present"; ok = (Test-Path -LiteralPath $shellStewardScript); detail = $shellStewardScript },
    [pscustomobject]@{ name = "shell_steward_state_healthy"; ok = $shellStewardStateHealthy; detail = $(if ($null -ne $shellStewardState) { "state=$($shellStewardState.status), updated_at=$($shellStewardState.updated_at)" } else { $shellStewardStatePath }) },
    [pscustomobject]@{ name = "shell_steward_process_visible"; ok = ($shellStewardStateHealthy -or $shellStewardProcesses.Count -gt 0); detail = $(if ($shellStewardStateHealthy) { "fresh state file used; skipped unbounded process probe" } else { "$($shellStewardProcesses.Count) matching process(es)" }) },
    [pscustomobject]@{ name = "automation_files_visible"; ok = ($automationFiles.Count -gt 0); detail = "$($automationFiles.Count) automation file(s)" },
    [pscustomobject]@{ name = "active_work_registry_visible"; ok = (Test-Path -LiteralPath $activeWorkRegistryPath); detail = (Get-FileDetail -Path $activeWorkRegistryPath) },
    [pscustomobject]@{ name = "active_work_registry_recent"; ok = (Test-RecentFile -Path $activeWorkRegistryPath -MaxAgeHours 2); detail = (Get-FileDetail -Path $activeWorkRegistryPath) },
    [pscustomobject]@{ name = "lane_leases_recent"; ok = (Test-RecentFile -Path $laneLeasesPath -MaxAgeHours 24); detail = (Get-FileDetail -Path $laneLeasesPath) },
    [pscustomobject]@{ name = "command_inbox_recent"; ok = (Test-RecentFile -Path $commandInboxPath -MaxAgeHours 24); detail = (Get-FileDetail -Path $commandInboxPath) },
    [pscustomobject]@{ name = "project_repo_visible"; ok = $gitStatus.is_repo; detail = $ProjectRoot }
)

$failed = @($checks | Where-Object { $_.ok -ne $true })
$result = [pscustomobject][ordered]@{
    generated_at = $now.ToString("o")
    source = "ai-manager-always-on-status"
    project_root = $ProjectRoot
    severity = if ($failed.Count -eq 0) { "routine" } else { "attention" }
    summary = if ($failed.Count -eq 0) {
        "DONT_NOTIFY - AI Manager always-on basics and movement truth are present."
    } else {
        "CHECK - always-on basics need attention: " + (($failed | Select-Object -ExpandProperty name) -join ", ")
    }
    checks = $checks
    git = $gitStatus
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 8
} else {
    $result.summary
}

if ($result.severity -ne "routine") { exit 2 }
