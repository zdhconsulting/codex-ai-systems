param(
    [string] $CodexHome = "",
    [string] $DbPath = "",
    [int] $KeepMrSeoAutomation = 0,
    [int] $KeepBossmanAutomation = 1,
    [int] $KeepOtherAutomation = 2,
    [int] $ArchiveWorktreeOlderThanHours = 72,
    [switch] $DryRun,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$DbPath = if ($DbPath) {
    $DbPath
} elseif (Test-Path -LiteralPath (Join-Path $CodexHome "state_5.sqlite")) {
    Join-Path $CodexHome "state_5.sqlite"
} else {
    Join-Path $CodexHome "sqlite\state_5.sqlite"
}
$logDir = Join-Path $CodexHome "logs"
$auditPath = Join-Path $logDir "thread-hygiene-last.json"

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

if (-not (Test-Path -LiteralPath $DbPath)) {
    throw "SQLite state file not found: $DbPath"
}
if (-not $DryRun) {
    $running = @(Get-CodexDesktopProcess)
    if ($running.Count -gt 0) {
        $ids = ($running | Select-Object -ExpandProperty Id) -join ", "
        throw "Refusing to archive threads while Codex Desktop is running. Run codex-thread-hygiene-after-exit.cmd instead. Running process ids: $ids"
    }
}

$tmpPy = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
$tmpReport = [System.IO.Path]::GetTempFileName()
$python = @'
import argparse
import json
import re
import sqlite3
import time
from collections import defaultdict

def norm_path(value):
    value = (value or "").replace("/", "\\")
    if value.startswith("\\\\?\\"):
        value = value[4:]
    return value.rstrip("\\").lower()

def automation_id(title):
    m = re.search(r"(?im)^Automation ID:\s*([^\r\n]+)", title or "")
    if m:
        return m.group(1).strip()
    first = (title or "").splitlines()[0].strip()
    return first[:120] or "automation"

def automation_kind(row):
    cwd = norm_path(row["cwd"])
    title = row["title"] or ""
    first = title.splitlines()[0].strip().lower()
    aid = automation_id(title).lower()
    signal = f"{cwd} {aid} {first}"
    if "mr.seo" in signal or "mr seo" in signal or "mr-seo" in signal:
        return "mrseo"
    if "bossman" in signal:
        return "bossman"
    return "other"

def keep_count_for_kind(kind, args):
    if kind == "mrseo":
        return args.keep_mr_seo
    if kind == "bossman":
        return args.keep_bossman
    return args.keep_other

def automation_group_key(row):
    kind = automation_kind(row)
    aid = automation_id(row["title"] or "")
    if kind == "mrseo":
        return (kind, "all-mrseo-automation")
    if kind == "bossman":
        return (kind, aid)
    return (kind, aid, norm_path(row["cwd"]))

def is_protected_thread(row):
    title = row["title"] or ""
    lines = title.splitlines()
    first = lines[0].strip().lower() if lines else ""
    protected_first_lines = {
        "ai manager",
        "ai manager`",
        "bossman",
        "bossman controller / critical only",
        "bossman critical alerts only",
        "optimize ai systems",
    }
    return first in protected_first_lines

parser = argparse.ArgumentParser()
parser.add_argument("--db", required=True)
parser.add_argument("--report", required=True)
parser.add_argument("--apply", action="store_true")
parser.add_argument("--keep-mr-seo", type=int, default=1)
parser.add_argument("--keep-bossman", type=int, default=2)
parser.add_argument("--keep-other", type=int, default=2)
parser.add_argument("--worktree-hours", type=int, default=72)
args = parser.parse_args()

now_ms = int(time.time() * 1000)
worktree_cutoff_ms = now_ms - (args.worktree_hours * 60 * 60 * 1000)
con = sqlite3.connect(args.db)
con.row_factory = sqlite3.Row
rows = con.execute("""
    select
        t.id, t.title, t.cwd, t.archived, t.updated_at_ms, t.thread_source,
        t.agent_role, t.preview, t.git_origin_url, e.status as spawn_status
    from threads t
    left join thread_spawn_edges e on e.child_thread_id = t.id
    where t.archived = 0
    order by t.updated_at_ms desc
""").fetchall()

candidates = {}
keep_notes = []

automation_groups = defaultdict(list)
for row in rows:
    title = row["title"] or ""
    if title.startswith("Automation:"):
        key = automation_group_key(row)
        automation_groups[key].append(row)

for key, group in automation_groups.items():
    group = sorted(group, key=lambda r: r["updated_at_ms"] or 0, reverse=True)
    keep_n = max(0, keep_count_for_kind(key[0], args))
    for row in group[:keep_n]:
        keep_notes.append({
            "id": row["id"],
            "title": (row["title"] or "")[:160],
            "reason": f"kept latest {keep_n} for automation group {key[1]}",
        })
    for row in group[keep_n:]:
        candidates[row["id"]] = {
            "id": row["id"],
            "title": (row["title"] or "")[:160],
            "cwd": row["cwd"],
            "updated_at_ms": row["updated_at_ms"],
            "reason": f"historical automation run; kept latest {keep_n} for {key[1]}",
        }

for row in rows:
    title = row["title"] or ""
    if row["id"] in candidates:
        continue
    if is_protected_thread(row):
        continue
    if row["spawn_status"] == "closed":
        candidates[row["id"]] = {
            "id": row["id"],
            "title": title[:160],
            "cwd": row["cwd"],
            "updated_at_ms": row["updated_at_ms"],
            "reason": "closed subagent/work lane",
        }
        continue
    if "\\.codex\\worktrees\\" in norm_path(row["cwd"]) and (row["updated_at_ms"] or 0) < worktree_cutoff_ms:
        candidates[row["id"]] = {
            "id": row["id"],
            "title": title[:160],
            "cwd": row["cwd"],
            "updated_at_ms": row["updated_at_ms"],
            "reason": f"stale temporary worktree thread older than {args.worktree_hours}h",
        }
        continue
    if title.startswith("Reply with exactly:") and "codexui" in norm_path(row["cwd"]):
        candidates[row["id"]] = {
            "id": row["id"],
            "title": title[:160],
            "cwd": row["cwd"],
            "updated_at_ms": row["updated_at_ms"],
            "reason": "old bridge test thread",
        }

archive_list = sorted(candidates.values(), key=lambda item: item["updated_at_ms"] or 0, reverse=True)
if args.apply and archive_list:
    with con:
        con.executemany(
            "update threads set archived = 1, archived_at = ? where id = ?",
            [(now_ms, item["id"]) for item in archive_list],
        )
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")

remaining_counts = []
for row in con.execute("select cwd, count(*) as n from threads where archived=0 group by cwd order by n desc"):
    remaining_counts.append({"cwd": row["cwd"], "count": row["n"]})

report = {
    "apply": bool(args.apply),
    "archive_count": len(archive_list),
    "archive": archive_list,
    "kept": keep_notes[:100],
    "remaining_open_by_cwd": remaining_counts,
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
            Copy-Item -LiteralPath $candidate -Destination "$candidate.bak-thread-hygiene-$stamp" -Force
        }
    }
}

$argsList = @(
    "--db", $DbPath,
    "--report", $tmpReport,
    "--keep-mr-seo", $KeepMrSeoAutomation,
    "--keep-bossman", $KeepBossmanAutomation,
    "--keep-other", $KeepOtherAutomation,
    "--worktree-hours", $ArchiveWorktreeOlderThanHours
)
if (-not $DryRun) { $argsList += "--apply" }
& python $tmpPy @argsList
if ($LASTEXITCODE -ne 0) {
    throw "Thread hygiene failed with exit code $LASTEXITCODE"
}

$report = Get-Content -Raw -LiteralPath $tmpReport | ConvertFrom-Json
Write-Utf8NoBomFile -Path $auditPath -Text ($report | ConvertTo-Json -Depth 100)
Remove-Item -LiteralPath $tmpPy, $tmpReport -Force -ErrorAction SilentlyContinue

$result = [pscustomobject]@{
    dryRun = [bool] $DryRun
    sqlitePath = $DbPath
    auditPath = $auditPath
    archiveCount = $report.archive_count
    sample = @($report.archive | Select-Object -First 12)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    if ($DryRun) {
        "Dry-run would archive $($report.archive_count) inactive/noisy Codex threads."
    } else {
        "Archived $($report.archive_count) inactive/noisy Codex threads."
    }
    "Audit: $auditPath"
    foreach ($item in @($report.archive | Select-Object -First 12)) {
        " - $($item.title) [$($item.reason)]"
    }
}
