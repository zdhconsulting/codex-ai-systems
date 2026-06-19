param(
    [string] $CodexHome = "",
    [string] $CommandCenterRoot = "C:\Users\zev\OneDrive\Documents\New project 2",
    [switch] $Apply,
    [switch] $ArmAfterExitCleanup,
    [switch] $SortByRecent,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$globalStatePath = Join-Path $CodexHome ".codex-global-state.json"
$agentRegistryPath = Join-Path $CommandCenterRoot "data\command-center\agent-registry.json"
$projectRegistryPath = Join-Path $CommandCenterRoot "data\command-center\project-registry.json"
$logDir = Join-Path $CodexHome "logs"
$reportPath = Join-Path $logDir "sidebar-reconciler-last.json"
$hygieneScript = Join-Path $CodexHome "scripts\codex-thread-hygiene.ps1"
$afterExitScript = Join-Path $CodexHome "scripts\codex-thread-hygiene-after-exit.ps1"

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Utf8NoBomFile {
    param([string] $Path, [string] $Text)
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

foreach ($required in @($globalStatePath, $agentRegistryPath, $projectRegistryPath, $hygieneScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required sidebar reconciler input not found: $required"
    }
}

$tmpPy = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
$tmpReport = [System.IO.Path]::GetTempFileName()
$python = @'
import argparse
import copy
import json
import os
import sqlite3
import time
from pathlib import Path

def read_json(path):
    with open(path, "r", encoding="utf-8-sig") as fh:
        return json.load(fh)

def write_json(path, data):
    raw = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    Path(path).write_text(raw, encoding="utf-8")

def norm_path(value):
    value = (value or "").replace("/", "\\")
    if value.startswith("\\\\?\\"):
        value = value[4:]
    return value.rstrip("\\").lower()

def display_path(value):
    return (value or "").replace("/", "\\").rstrip("\\")

def first_line(value):
    return (value or "").splitlines()[0].strip()

parser = argparse.ArgumentParser()
parser.add_argument("--codex-home", required=True)
parser.add_argument("--global-state", required=True)
parser.add_argument("--agent-registry", required=True)
parser.add_argument("--project-registry", required=True)
parser.add_argument("--report", required=True)
parser.add_argument("--apply", action="store_true")
parser.add_argument("--sort-by-recent", action="store_true")
args = parser.parse_args()

codex_home = Path(args.codex_home)
global_state_path = Path(args.global_state)
agent_registry = read_json(args.agent_registry)
project_registry = read_json(args.project_registry)
global_state = read_json(global_state_path)
original_state = copy.deepcopy(global_state)

agents = agent_registry.get("agents", [])
projects = project_registry.get("projects", [])

expected_pin_ids = []
expected_pin_titles = {}
for agent in agents:
    thread_id = agent.get("thread_id")
    if not thread_id:
        continue
    if agent.get("status") not in (None, "active"):
        continue
    if agent.get("thread_binding_status") not in (None, "bound"):
        continue
    if agent.get("type") not in ("persistent_lane",):
        continue
    expected_pin_ids.append(thread_id)
    expected_pin_titles[thread_id] = agent.get("display_name") or agent.get("role_name") or agent.get("id")

seen = set()
expected_pin_ids = [tid for tid in expected_pin_ids if not (tid in seen or seen.add(tid))]
current_pin_ids = list(global_state.get("pinned-thread-ids", []))
missing_pins = [tid for tid in expected_pin_ids if tid not in current_pin_ids]
extra_pins = [tid for tid in current_pin_ids if tid not in expected_pin_ids]

curated_roots = [
    ("C:\\Users\\zev\\Documents\\Codex\\00-active-now", "00 RECENT / Active Now"),
    ("C:\\Users\\zev\\Documents\\Codex\\00-agent-chats", "00 AGENTS / Named Agent Chats"),
    ("C:\\Users\\zev\\OneDrive\\Documents\\New project 2", "01 COMMAND / ZDH Center"),
    ("C:\\repos\\bossman", "02 SYSTEM / Bossman Dispatch"),
    ("C:\\repos\\codex-ai-systems", "03 SYSTEM / Codex OS"),
    ("C:\\repos\\Mr.SEO", "04 SYSTEM / Mr.SEO"),
    ("C:\\Repos\\ZDH-AI-Dashboard", "05 SYSTEM / ZDH Dashboard"),
]

project_label_overrides = {
    "zdh-sales": "10 PROJECT / ZDH Sales",
    "zdh-consulting": "11 PROJECT / ZDH Consulting",
    "web-design-israel": "12 PROJECT / Web Design Israel",
    "explainmybusiness": "13 PROJECT / ExplainMyBusiness",
    "botox-marketplace": "14 PROJECT / Botox Marketplace",
    "botox-israel-thea": "15 PROJECT / Botox Israel / THEA",
    "israel-offshore": "16 PROJECT / Israel Offshore",
    "israel-digital-army": "17 PROJECT / Israel Digital Army",
    "zevhecht-com": "40 PROJECT / ZevHecht.com",
    "english-comedy-tlv": "70 QA / English Comedy TLV",
    "zdhbook": "80 PROJECT / zdhbook",
}

for project in projects:
    repo_path = project.get("repo_path")
    if not repo_path:
        continue
    project_id = project.get("id")
    label = project_label_overrides.get(project_id)
    if not label:
        continue
    curated_roots.append((display_path(repo_path), label))

curated_unique = []
seen_paths = set()
for root, label in curated_roots:
    key = norm_path(root)
    if not key or key in seen_paths:
        continue
    seen_paths.add(key)
    curated_unique.append((display_path(root), label))

retired_roots = {
    norm_path("C:\\repos\\book"): "retired zdhbook clone; canonical project is book-live-repo",
}
current_roots = [
    root for root in list(global_state.get("electron-saved-workspace-roots", []))
    if norm_path(root) not in retired_roots
]
label_key = "electron-workspace-root-labels"
legacy_label_key = "electron-saved-workspace-root-labels"
labels = global_state.get(label_key)
if not isinstance(labels, dict):
    labels = global_state.get(legacy_label_key)
if not isinstance(labels, dict):
    labels = {}
labels_by_norm = {}
for existing_root, existing_label in labels.items():
    labels_by_norm[norm_path(existing_root)] = existing_label
retired_removed = []
for existing_root in list(labels.keys()):
    key = norm_path(existing_root)
    if key in retired_roots:
        retired_removed.append({"root": existing_root, "reason": retired_roots[key]})
        labels.pop(existing_root, None)

current_norm_to_root = {norm_path(root): root for root in current_roots}
desired_roots = []
missing_roots = []
label_mismatches = []
for root, label in curated_unique:
    key = norm_path(root)
    actual_root = current_norm_to_root.get(key, root)
    desired_roots.append(actual_root)
    if key not in current_norm_to_root:
        missing_roots.append({"root": root, "label": label})
    current_label = labels.get(actual_root)
    if current_label is None:
        current_label = labels_by_norm.get(key)
    if current_label != label:
        label_mismatches.append({"root": actual_root, "current": current_label, "desired": label})
    labels[actual_root] = label

extra_roots = []
desired_norms = {norm_path(root) for root in desired_roots}
for root in current_roots:
    if norm_path(root) not in desired_norms:
        extra_roots.append({"root": root, "label": labels.get(root)})
        desired_roots.append(root)

db_paths = [
    codex_home / "sqlite" / "state_5.sqlite",
    codex_home / "state_5.sqlite",
]

db_reports = []
recent_by_root = {}
for db_path in db_paths:
    if not db_path.exists():
        db_reports.append({"path": str(db_path), "exists": False})
        continue
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    root_norms = {norm_path(root): root for root in desired_roots}
    for row in con.execute("select cwd, max(coalesce(updated_at_ms, updated_at * 1000, 0)) as latest from threads where archived=0 group by cwd"):
        cwd_key = norm_path(row["cwd"])
        if cwd_key in root_norms:
            root = root_norms[cwd_key]
            recent_by_root[root] = max(int(row["latest"] or 0), int(recent_by_root.get(root, 0) or 0))
    thread_ids = expected_pin_ids
    placeholders = ",".join("?" for _ in thread_ids) or "''"
    registered_rows = []
    if thread_ids:
        for row in con.execute(
            f"select id,title,archived,cwd,updated_at from threads where id in ({placeholders}) order by title",
            thread_ids,
        ):
            registered_rows.append({
                "id": row["id"],
                "title": first_line(row["title"]),
                "archived": bool(row["archived"]),
                "cwd": row["cwd"],
                "updated_at": row["updated_at"],
            })
    visible_noise = []
    noise_query = """
        select id,title,cwd,updated_at from threads
        where archived=0 and (
            title like 'Automation: Mr.SEO%' or
            title like 'Mr.SEO %' or
            title like 'Automation: Bossman%' or
            title like 'Bossman delivery lane%' or
            title like 'Bossman planner + public report%'
        )
        and title not like 'AGENT -%'
        and title not like 'MANAGER -%'
        and title != 'BOSSMAN - Manager'
        order by updated_at desc
        limit 50
    """
    for row in con.execute(noise_query):
        visible_noise.append({
            "id": row["id"],
            "title": first_line(row["title"]),
            "cwd": row["cwd"],
            "updated_at": row["updated_at"],
        })
    con.close()
    db_reports.append({
        "path": str(db_path),
        "exists": True,
        "registered_thread_count": len(registered_rows),
        "registered_threads": registered_rows,
        "visible_noise_count_sampled": len(visible_noise),
        "visible_noise_sample": visible_noise[:12],
    })

changes = {
    "pinned_ids": missing_pins or extra_pins,
    "roots": missing_roots or extra_roots or label_mismatches,
}

sort_mode = "registry_order"
if args.sort_by_recent:
    sort_mode = "recent_first"
    desired_roots = sorted(
        desired_roots,
        key=lambda root: (int(recent_by_root.get(root, 0) or 0), labels.get(root, "")),
        reverse=True,
    )

if args.apply:
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    backup_path = global_state_path.with_suffix(global_state_path.suffix + f".bak-sidebar-reconciler-{timestamp}")
    backup_path.write_text(json.dumps(original_state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    reconciled_pins = list(current_pin_ids)
    for tid in expected_pin_ids:
        if tid not in reconciled_pins:
            reconciled_pins.append(tid)
    global_state["pinned-thread-ids"] = reconciled_pins
    global_state["electron-saved-workspace-roots"] = desired_roots
    global_state[label_key] = labels
    if legacy_label_key in global_state:
        global_state[legacy_label_key] = labels
    project_order = list(global_state.get("project-order", []))
    ordered = []
    for root in desired_roots:
        if root not in ordered:
            ordered.append(root)
    for root in project_order:
        if norm_path(root) in retired_roots:
            continue
        if root not in ordered:
            ordered.append(root)
    global_state["project-order"] = ordered
    appearances = global_state.get("project-appearances")
    if not isinstance(appearances, dict):
        appearances = {}
    for root, label in labels.items():
        if root not in appearances:
            appearances[root] = {}
    for root in list(appearances.keys()):
        if norm_path(root) in retired_roots:
            appearances.pop(root, None)
    global_state["project-appearances"] = appearances
    write_json(global_state_path, global_state)
else:
    backup_path = None

report = {
    "schema_version": "0.1",
    "apply": bool(args.apply),
    "global_state_path": str(global_state_path),
    "backup_path": str(backup_path) if backup_path else None,
    "expected_pin_count": len(expected_pin_ids),
    "current_pin_count": len(current_pin_ids),
    "missing_pins": [{"thread_id": tid, "title": expected_pin_titles.get(tid)} for tid in missing_pins],
    "extra_pins": extra_pins,
    "desired_root_count": len(desired_roots),
    "current_root_count": len(current_roots),
    "missing_roots": missing_roots,
    "extra_roots": extra_roots,
    "retired_roots_removed": retired_removed,
    "label_mismatches": label_mismatches,
    "db_reports": db_reports,
    "sort_mode": sort_mode,
    "recent_by_root": recent_by_root,
    "needs_after_exit_cleanup": any(item.get("visible_noise_count_sampled", 0) > 0 for item in db_reports),
    "changed": bool(changes["pinned_ids"] or changes["roots"]),
}

write_json(args.report, report)
'@

Write-Utf8NoBomFile -Path $tmpPy -Text $python

$argsList = @(
    "--codex-home", $CodexHome,
    "--global-state", $globalStatePath,
    "--agent-registry", $agentRegistryPath,
    "--project-registry", $projectRegistryPath,
    "--report", $tmpReport
)
if ($Apply) { $argsList += "--apply" }
if ($SortByRecent) { $argsList += "--sort-by-recent" }
& python $tmpPy @argsList
if ($LASTEXITCODE -ne 0) {
    throw "Sidebar reconciler failed with exit code $LASTEXITCODE"
}

$report = Get-Content -Raw -LiteralPath $tmpReport | ConvertFrom-Json
Write-Utf8NoBomFile -Path $reportPath -Text ($report | ConvertTo-Json -Depth 100)
Remove-Item -LiteralPath $tmpPy, $tmpReport -Force -ErrorAction SilentlyContinue

$runningCodex = @(Get-CodexDesktopProcess)
$armed = $false
if ($ArmAfterExitCleanup) {
    if (-not (Test-Path -LiteralPath $afterExitScript)) {
        throw "After-exit cleanup script not found: $afterExitScript"
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $afterExitScript) -WindowStyle Hidden
    $armed = $true
}

$summary = [pscustomobject]@{
    apply = [bool] $Apply
    reportPath = $reportPath
    expectedPins = $report.expected_pin_count
    missingPins = @($report.missing_pins).Count
    extraPins = @($report.extra_pins).Count
    desiredRoots = $report.desired_root_count
    missingRoots = @($report.missing_roots).Count
    extraRoots = @($report.extra_roots).Count
    labelMismatches = @($report.label_mismatches).Count
    sortMode = $report.sort_mode
    needsAfterExitCleanup = [bool] $report.needs_after_exit_cleanup
    afterExitCleanupArmed = $armed
    codexDesktopRunning = $runningCodex.Count -gt 0
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 10
} else {
    "Codex sidebar reconciler"
    "Apply: $($summary.apply)"
    "Report: $($summary.reportPath)"
    "Pins: expected=$($summary.expectedPins), missing=$($summary.missingPins), extra=$($summary.extraPins)"
    "Projects: desired roots=$($summary.desiredRoots), missing=$($summary.missingRoots), extra=$($summary.extraRoots), label mismatches=$($summary.labelMismatches)"
    "Sort mode: $($summary.sortMode)"
    "Thread cleanup needed after exit: $($summary.needsAfterExitCleanup)"
    "After-exit cleanup armed: $($summary.afterExitCleanupArmed)"
}
