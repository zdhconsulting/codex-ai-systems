param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string] $DbPath = "",
    [switch] $Apply,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$StatePath = if ($StatePath) { $StatePath } else { Join-Path $CodexHome ".codex-global-state.json" }
$DbPath = if ($DbPath) {
    $DbPath
} elseif (Test-Path -LiteralPath (Join-Path $CodexHome "state_5.sqlite")) {
    Join-Path $CodexHome "state_5.sqlite"
} else {
    Join-Path $CodexHome "sqlite\state_5.sqlite"
}
$LogDir = Join-Path $CodexHome "logs"
$ReportPath = Join-Path $LogDir "narrow-thread-rehome-last.json"

function Write-Utf8NoBomFile {
    param(
        [string] $Path,
        [string] $Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-CodexDesktopProcess {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            $path = $_.Path
            $isPackagedApp = $path -match "\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\"
            $isUnifiedDesktop = ($_.ProcessName -ieq "ChatGPT") -and ($path -match "\\app\\ChatGPT\.exe$")
            $isLegacyDesktop = ($_.ProcessName -ieq "Codex") -and ($path -match "\\app\\Codex\.exe$")
            $isPackagedApp -and ($isUnifiedDesktop -or $isLegacyDesktop)
        } catch {
            $false
        }
    }
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    throw "State file not found: $StatePath"
}
if (-not (Test-Path -LiteralPath $DbPath)) {
    throw "SQLite state file not found: $DbPath"
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python not found"
}
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
if ($Apply) {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -gt 0) {
        $ids = ($running | Select-Object -ExpandProperty Id) -join ", "
        throw "Refusing to rehome threads while Codex Desktop is running. Use codex-narrow-thread-rehome-after-exit.cmd. Running process ids: $ids"
    }
}

$Mappings = @(
    @{ Id = "019ea0a7-1056-7c00-84f1-12fa689e503c"; Title = "bossman"; Target = "C:\Repos\bossman" },
    @{ Id = "019e9f8f-7f6d-7691-8761-9b0519c35585"; Title = "ZDH Sales"; Target = "C:\Repos\zdhsales" },
    @{ Id = "019e9f90-0538-7562-b162-ae6a9b802239"; Title = "Web Design Israel"; Target = "C:\Repos\webdesignisrael" },
    @{ Id = "019ea101-a815-7c53-b267-690028a4f137"; Title = "ExplainMyPitch"; Target = "C:\Repos\explainmybusiness" },
    @{ Id = "019ea9e3-fc7b-71c3-87ad-f984cb9e55fd"; Title = "Israel Digital Army"; Target = "C:\Repos\IsraelDigitalArmy.com" },
    @{ Id = "019eaa12-5d38-7d22-9b85-c8a7d34404ba"; Title = "Create site IsraelOffshore"; Target = "C:\Users\zev\OneDrive\Documents\IsraelOffshore" },
    @{ Id = "019ec577-5f43-7e00-a73a-379eedd53db5"; Title = "zdhbook"; Target = "C:\Repos\book" }
)

$ExistingMappings = @($Mappings | Where-Object { Test-Path -LiteralPath $_.Target })
$MissingTargets = @($Mappings | Where-Object { -not (Test-Path -LiteralPath $_.Target) })
$MappingPath = Join-Path $env:TEMP "codex-narrow-thread-rehome-map.json"
$PyPath = Join-Path $env:TEMP "codex-narrow-thread-rehome.py"
$DbReportPath = Join-Path $env:TEMP "codex-narrow-thread-rehome-db-report.json"
Write-Utf8NoBomFile -Path $MappingPath -Text ($ExistingMappings | ConvertTo-Json -Depth 5)

Write-Utf8NoBomFile -Path $PyPath -Text @'
import argparse
import json
import sqlite3

def norm(value):
    if not value:
        return ""
    value = value.replace("/", "\\")
    if value.startswith("\\\\?\\"):
        value = value[4:]
    while "\\\\" in value:
        value = value.replace("\\\\", "\\")
    return value.rstrip("\\").lower()

def extended(value):
    value = value.replace("/", "\\").rstrip("\\")
    if value.startswith("\\\\?\\"):
        return value
    return "\\\\?\\" + value

parser = argparse.ArgumentParser()
parser.add_argument("--db", required=True)
parser.add_argument("--mapping", required=True)
parser.add_argument("--report", required=True)
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()

with open(args.mapping, "r", encoding="utf-8-sig") as handle:
    mappings = json.load(handle)

connection = sqlite3.connect(args.db)
connection.row_factory = sqlite3.Row
changes = []
missing = []

for mapping in mappings:
    row = connection.execute(
        "select id, title, cwd, archived from threads where id = ?",
        (mapping["Id"],),
    ).fetchone()
    if not row:
        missing.append({"id": mapping["Id"], "target": mapping["Target"], "reason": "thread not found"})
        continue
    target = mapping["Target"]
    new_cwd = extended(target)
    old_cwd = row["cwd"] or ""
    status = "unchanged" if norm(old_cwd) == norm(target) else "would_update"
    if args.apply and status == "would_update":
        connection.execute("update threads set cwd = ? where id = ?", (new_cwd, mapping["Id"]))
        status = "updated"
    changes.append({
        "id": mapping["Id"],
        "expected_title": mapping.get("Title", ""),
        "actual_title": row["title"] or "",
        "old_cwd": old_cwd,
        "new_cwd": new_cwd,
        "target": target,
        "archived": int(row["archived"] or 0),
        "status": status,
    })

if args.apply:
    connection.commit()
connection.close()

with open(args.report, "w", encoding="utf-8") as handle:
    json.dump({"apply": bool(args.apply), "changes": changes, "missing": missing}, handle, indent=2)
'@

$argsList = @("--db", $DbPath, "--mapping", $MappingPath, "--report", $DbReportPath)
if ($Apply) { $argsList += "--apply" }
& python $PyPath @argsList
if ($LASTEXITCODE -ne 0) {
    throw "SQLite rehome helper failed with exit code $LASTEXITCODE"
}

$DbReport = Get-Content -Raw -LiteralPath $DbReportPath | ConvertFrom-Json
$StateBackup = $null
$DbBackups = @()

if ($Apply) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $StateBackup = "$StatePath.bak-narrow-thread-rehome-$stamp"
    Copy-Item -LiteralPath $StatePath -Destination $StateBackup -Force
    foreach ($suffix in @("", "-wal", "-shm")) {
        $candidate = "$DbPath$suffix"
        if (Test-Path -LiteralPath $candidate) {
            $backup = "$candidate.bak-narrow-thread-rehome-$stamp"
            Copy-Item -LiteralPath $candidate -Destination $backup -Force
            $DbBackups += $backup
        }
    }

    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    if (-not $state.PSObject.Properties["thread-workspace-root-hints"]) {
        $state | Add-Member -NotePropertyName "thread-workspace-root-hints" -NotePropertyValue ([pscustomobject]@{})
    }
    $hints = $state."thread-workspace-root-hints"
    foreach ($mapping in $ExistingMappings) {
        $hints | Add-Member -NotePropertyName $mapping.Id -NotePropertyValue $mapping.Target -Force
    }
    Write-Utf8NoBomFile -Path $StatePath -Text ($state | ConvertTo-Json -Depth 100 -Compress)
}

$Report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    apply = [bool]$Apply
    state_path = $StatePath
    db_path = $DbPath
    state_backup = $StateBackup
    db_backups = $DbBackups
    mapping_count = $Mappings.Count
    existing_mapping_count = $ExistingMappings.Count
    missing_targets = $MissingTargets
    changes = $DbReport.changes
    missing_threads = $DbReport.missing
}
Write-Utf8NoBomFile -Path $ReportPath -Text ($Report | ConvertTo-Json -Depth 20)

if ($Json) {
    $Report | ConvertTo-Json -Depth 20
    exit 0
}

Write-Host "Narrow Codex thread rehome"
Write-Host "Apply: $([bool]$Apply)"
Write-Host "Report: $ReportPath"
foreach ($change in @($Report.changes)) {
    Write-Host "$($change.status): $($change.actual_title) [$($change.id)] -> $($change.target)"
}
if ($Report.missing_threads.Count -gt 0) {
    Write-Host "Missing threads: $($Report.missing_threads.Count)"
}
if ($Report.missing_targets.Count -gt 0) {
    Write-Host "Missing target paths: $($Report.missing_targets.Count)"
}
