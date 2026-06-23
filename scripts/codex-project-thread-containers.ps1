param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string] $DbPath = "",
    [switch] $DryRun,
    [switch] $IncludeArchived,
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
$logDir = Join-Path $CodexHome "logs"
$auditPath = Join-Path $logDir "project-thread-containers-last.json"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

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
            ($_.ProcessName -in @("Codex", "codex")) -and ($_.Path -match "\\WindowsApps\\OpenAI\.Codex_.*\\app\\")
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
if (-not $DryRun) {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -gt 0) {
        $ids = ($running | Select-Object -ExpandProperty Id) -join ", "
        throw "Refusing to re-home threads while Codex Desktop is running. Run codex-project-containers-after-exit.cmd instead. Running process ids: $ids"
    }
}

$sourceRoot = "C:\Users\zev\OneDrive\Documents\New project 2"
$rules = @(
    @{ id = "bossman-chat"; target = "C:\Repos\bossman"; titleRegex = "(?i)^BOSSMAN - (Manager|Critical Escalations|Heartbeat / Reports)$"; reason = "Only registered Bossman operator chats belong in the Bossman project container; disposable workers and reusable lanes stay out of pinned project clutter." },
    @{ id = "mr-seo-project"; target = "C:\repos\Mr.SEO"; titleRegex = "(?i)^(SPECIALIST - Mr SEO|Mr\.SEO|Mr SEO)"; reason = "Mr.SEO lanes belong in the Mr.SEO project container." },
    @{ id = "zdh-sales-project"; target = "C:\Repos\zdhsales"; titleRegex = "(?i)^PROJECT - ZDH Sales$"; reason = "ZDH Sales project lane belongs in the ZDH Sales repo container." },
    @{ id = "web-design-israel-project"; target = "C:\Repos\webdesignisrael"; titleRegex = "(?i)^PROJECT - Web Design Israel$"; reason = "Web Design Israel project lane belongs in the Web Design Israel repo container." },
    @{ id = "israel-digital-army-project"; target = "C:\Repos\IsraelDigitalArmy.com"; titleRegex = "(?i)^PROJECT - Israel Digital Army$"; reason = "Israel Digital Army project lane belongs in the Israel Digital Army repo container." },
    @{ id = "explain-my-business-project"; target = "C:\Repos\explainmybusiness"; titleRegex = "(?i)^PROJECT - ExplainMyBusiness$"; reason = "ExplainMyBusiness project lane belongs in the ExplainMyBusiness repo container." },
    @{ id = "israel-offshore-project"; target = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; titleRegex = "(?i)^PROJECT - Israel Offshore$"; reason = "Israel Offshore project lane belongs in the Israel Offshore repo container." },
    @{ id = "zdhbook-project"; target = "C:\Repos\book"; titleRegex = "(?i)^PROJECT - zdhbook$"; reason = "The live book lane belongs in the zdhbook repo container." },
    @{ id = "zev-hecht-project"; target = "C:\Users\zev\OneDrive\Documents\zevhecht.com"; titleRegex = "(?i)^(PROJECT - Zev Hecht|zevhecht\.com)$"; reason = "Zev Hecht lanes belong in the zevhecht.com repo container." },
    @{ id = "english-comedy-title"; target = "C:\repos\EnglishComedyTLV"; titleRegex = "(?i)(Yohay Sponder Website|English Comedy TLV|englishcomedytelaviv|supabase in englishcomedytelaviv|based on the images in C:\\Users\\zev\\OneDrive\\Desktop\\English Comedy TLV)"; reason = "English Comedy TLV/Yohay website lanes belong in the EnglishComedyTLV repo container." },
    @{ id = "botox-marketplace-project"; target = "C:\Users\zev\Documents\Codex\2026-06-05\botox-marketplace"; titleRegex = "(?i)^PROJECT - Botox Marketplace$"; reason = "Botox Marketplace project lanes belong in the Botox Marketplace project container." }
)

$existingRules = @($rules | Where-Object { Test-Path -LiteralPath $_.target })
$skippedRules = @($rules | Where-Object { -not (Test-Path -LiteralPath $_.target) })

$tmpRules = [System.IO.Path]::GetTempFileName()
$tmpReport = [System.IO.Path]::GetTempFileName()
$tmpPy = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
Write-Utf8NoBomFile -Path $tmpRules -Text ($existingRules | ConvertTo-Json -Depth 10 -Compress)

$python = @'
import argparse
import json
import re
import sqlite3

def norm_path(value):
    if not value:
        return ""
    value = value.replace("/", "\\")
    if value.startswith("\\\\?\\"):
        value = value[4:]
    while "\\\\" in value:
        value = value.replace("\\\\", "\\")
    return value.rstrip("\\").lower()

def extended_path(value):
    value = value.replace("/", "\\").rstrip("\\")
    if value.startswith("\\\\?\\"):
        return value
    return "\\\\?\\" + value

parser = argparse.ArgumentParser()
parser.add_argument("--db", required=True)
parser.add_argument("--rules", required=True)
parser.add_argument("--source", required=True)
parser.add_argument("--report", required=True)
parser.add_argument("--apply", action="store_true")
parser.add_argument("--include-archived", action="store_true")
args = parser.parse_args()

with open(args.rules, "r", encoding="utf-8-sig") as fh:
    rules = json.load(fh)

source_norm = norm_path(args.source)
con = sqlite3.connect(args.db)
con.row_factory = sqlite3.Row
where = "where lower(replace(cwd, '/', '\\')) like ?"
params = [f"%{source_norm.split(':', 1)[-1]}%"]
rows = con.execute(
    "select id, title, cwd, git_origin_url, archived from threads " + where + " order by updated_at_ms desc",
    params,
).fetchall()

moves = []
uncertain = []
for row in rows:
    old_cwd = row["cwd"] or ""
    if norm_path(old_cwd) != source_norm:
        continue
    if int(row["archived"] or 0) and not args.include_archived:
        continue
    title = row["title"] or ""
    origin = row["git_origin_url"] or ""
    matched = None
    for rule in rules:
        title_regex = rule.get("titleRegex")
        origin_regex = rule.get("originRegex")
        title_ok = bool(title_regex and re.search(title_regex, title))
        origin_ok = bool(origin_regex and re.search(origin_regex, origin))
        if title_ok or origin_ok:
            matched = rule
            break
    if not matched:
        uncertain.append({
            "id": row["id"],
            "title": title[:160],
            "cwd": old_cwd,
            "git_origin_url": origin,
            "archived": int(row["archived"] or 0),
        })
        continue
    target = matched["target"]
    new_cwd = extended_path(target)
    if norm_path(old_cwd) == norm_path(target):
        continue
    moves.append({
        "id": row["id"],
        "title": title[:160],
        "old_cwd": old_cwd,
        "new_cwd": new_cwd,
        "target": target,
        "rule_id": matched.get("id"),
        "reason": matched.get("reason"),
        "git_origin_url": origin,
        "archived": int(row["archived"] or 0),
    })

if args.apply and moves:
    with con:
        for move in moves:
            con.execute("update threads set cwd = ? where id = ?", (move["new_cwd"], move["id"]))

report = {
    "db_path": args.db,
    "source_root": args.source,
    "apply": bool(args.apply),
    "include_archived": bool(args.include_archived),
    "move_count": len(moves),
    "moves": moves,
    "uncertain_count": len(uncertain),
    "uncertain": uncertain[:100],
}
with open(args.report, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
con.close()
'@
Write-Utf8NoBomFile -Path $tmpPy -Text $python

if (-not $DryRun) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    foreach ($suffix in @("", "-wal", "-shm")) {
        $candidate = "$DbPath$suffix"
        if (Test-Path -LiteralPath $candidate) {
            Copy-Item -LiteralPath $candidate -Destination "$candidate.bak-project-thread-containers-$stamp" -Force
        }
    }
}

$argsList = @("--db", $DbPath, "--rules", $tmpRules, "--source", $sourceRoot, "--report", $tmpReport)
if (-not $DryRun) { $argsList += "--apply" }
if ($IncludeArchived) { $argsList += "--include-archived" }
& python $tmpPy @argsList
if ($LASTEXITCODE -ne 0) {
    throw "Thread re-home query failed with exit code $LASTEXITCODE"
}

$report = Get-Content -Raw -LiteralPath $tmpReport | ConvertFrom-Json
Write-Utf8NoBomFile -Path $auditPath -Text ($report | ConvertTo-Json -Depth 100)

if (-not $DryRun -and $report.move_count -gt 0) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $StatePath -Destination "$StatePath.bak-project-thread-containers-$stamp" -Force
    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    if (-not $state.PSObject.Properties["thread-workspace-root-hints"]) {
        $state | Add-Member -NotePropertyName "thread-workspace-root-hints" -NotePropertyValue ([pscustomobject]@{})
    }
    $hints = $state."thread-workspace-root-hints"
    foreach ($move in @($report.moves)) {
        $hints | Add-Member -NotePropertyName $move.id -NotePropertyValue $move.target -Force
    }
    if ($state.PSObject.Properties["projectless-thread-ids"]) {
        $movedIds = @($report.moves | ForEach-Object { $_.id })
        $state."projectless-thread-ids" = @($state."projectless-thread-ids" | Where-Object { $movedIds -notcontains $_ })
    }
    Write-Utf8NoBomFile -Path $StatePath -Text ($state | ConvertTo-Json -Depth 100 -Compress)
}

Remove-Item -LiteralPath $tmpRules, $tmpReport, $tmpPy -Force -ErrorAction SilentlyContinue

$result = [pscustomobject]@{
    dryRun = [bool] $DryRun
    sqlitePath = $DbPath
    auditPath = $auditPath
    moveCount = $report.move_count
    uncertainCount = $report.uncertain_count
    movedTitles = @($report.moves | ForEach-Object { $_.title })
    skippedMissingTargets = @($skippedRules | ForEach-Object { "$($_.id): $($_.target)" })
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    if ($DryRun) {
        "Dry-run found $($report.move_count) high-confidence thread container moves."
    } else {
        "Applied $($report.move_count) high-confidence thread container moves."
    }
    "Audit: $auditPath"
    if ($report.uncertain_count -gt 0) {
        "Left $($report.uncertain_count) ambiguous New Project 2 threads untouched."
    }
    foreach ($move in @($report.moves)) {
        " - $($move.title) -> $($move.target)"
    }
}
