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

$codexHome = Join-Path $env:USERPROFILE ".codex"
$backlogPath = Join-Path $codexHome "backlog\ai-manager-always-on-backlog.md"
$ownerButtonPath = Join-Path $codexHome "scripts\owner-button.cmd"
$shellStewardScript = Join-Path $codexHome "scripts\codex-shell-steward.ps1"
$automationRoot = Join-Path $codexHome "automations"

$automationFiles = @()
if (Test-Path -LiteralPath $automationRoot) {
    $automationFiles = @(Get-ChildItem -Path $automationRoot -Recurse -Filter automation.toml -ErrorAction SilentlyContinue)
}

$shellStewardProcesses = @(Get-CimInstance Win32_Process -Filter "name = 'powershell.exe' or name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { ([string]$_.CommandLine) -like "*codex-shell-steward.ps1*" })

$gitStatus = Get-GitStatus -Root $ProjectRoot
$now = [datetimeoffset](Get-Date)
$checks = @(
    [pscustomobject]@{ name = "backlog_present"; ok = (Test-Path -LiteralPath $backlogPath); detail = $backlogPath },
    [pscustomobject]@{ name = "owner_button_tool_present"; ok = (Test-Path -LiteralPath $ownerButtonPath); detail = $ownerButtonPath },
    [pscustomobject]@{ name = "shell_steward_script_present"; ok = (Test-Path -LiteralPath $shellStewardScript); detail = $shellStewardScript },
    [pscustomobject]@{ name = "shell_steward_process_visible"; ok = ($shellStewardProcesses.Count -gt 0); detail = "$($shellStewardProcesses.Count) matching process(es)" },
    [pscustomobject]@{ name = "automation_files_visible"; ok = ($automationFiles.Count -gt 0); detail = "$($automationFiles.Count) automation file(s)" },
    [pscustomobject]@{ name = "project_repo_visible"; ok = $gitStatus.is_repo; detail = $ProjectRoot }
)

$failed = @($checks | Where-Object { $_.ok -ne $true })
$result = [pscustomobject][ordered]@{
    generated_at = $now.ToString("o")
    source = "ai-manager-always-on-status"
    project_root = $ProjectRoot
    severity = if ($failed.Count -eq 0) { "routine" } else { "attention" }
    summary = if ($failed.Count -eq 0) {
        "DONT_NOTIFY - AI Manager always-on basics are present."
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
