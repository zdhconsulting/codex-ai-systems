param(
    [string] $CodexHome = "",
    [string] $OutputDir = "C:\Users\zev\Documents\Codex\00-active-now",
    [int] $Limit = 30,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$dbPath = Join-Path $CodexHome "state_5.sqlite"
$outPath = Join-Path $OutputDir "active-now.md"

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $dbPath)) {
    throw "Codex state DB not found: $dbPath"
}

$tmpPy = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".py")
$python = @'
import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path

def clean(value):
    return (value or "").replace("\\\\?\\", "").rstrip("\\")

def first_line(value):
    lines = (value or "").splitlines()
    if not lines:
        return "(untitled)"
    return lines[0].strip() or "(untitled)"

def fmt_ms(ms):
    if not ms:
        return "unknown"
    return dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")

parser = argparse.ArgumentParser()
parser.add_argument("--db", required=True)
parser.add_argument("--out", required=True)
parser.add_argument("--limit", type=int, default=30)
args = parser.parse_args()

con = sqlite3.connect(args.db)
con.row_factory = sqlite3.Row
rows = con.execute(
    """
    select id, title, cwd, model, thread_source, updated_at_ms
    from threads
    where archived = 0
    order by updated_at_ms desc
    limit ?
    """,
    (args.limit,),
).fetchall()
con.close()

lines = [
    "# Active Now",
    "",
    f"Generated: {dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
    "",
    "This folder is the visible sidebar anchor for the most recently active Codex work.",
    "",
    "| Updated | Source | Thread | Project / Folder |",
    "|---|---|---|---|",
]
items = []
for row in rows:
    item = {
        "updated": fmt_ms(row["updated_at_ms"]),
        "source": row["thread_source"] or row["model"] or "",
        "thread": first_line(row["title"]),
        "thread_id": row["id"],
        "cwd": clean(row["cwd"]),
    }
    items.append(item)
    safe_thread = item["thread"].replace("|", "\\|")
    safe_cwd = item["cwd"].replace("|", "\\|")
    lines.append(f"| {item['updated']} | {item['source']} | `{safe_thread}` | `{safe_cwd}` |")

Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"output": args.out, "count": len(items), "items": items[:10]}, indent=2))
'@

[System.IO.File]::WriteAllText($tmpPy, $python, [System.Text.UTF8Encoding]::new($false))
$raw = & python $tmpPy --db $dbPath --out $outPath --limit $Limit
Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue

if ($Json) {
    $raw
} else {
    "Active Now written: $outPath"
    $raw
}
