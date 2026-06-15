param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string] $ThreadsDbPath = "",
    [switch] $NoPatchThreadAssignments,
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$StatePath = if ($StatePath) { $StatePath } else { Join-Path $CodexHome ".codex-global-state.json" }
$ThreadsDbPath = if ($ThreadsDbPath) { $ThreadsDbPath } else { Join-Path $CodexHome "sqlite\state_5.sqlite" }

function Write-Utf8NoBomFile {
    param(
        [string] $Path,
        [string] $Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Remove-PropertyIfPresent {
    param(
        [object] $Object,
        [string] $Name
    )

    if ($Object -and $Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Get-ExtendedWindowsPath {
    param([string] $Path)
    if ($Path.StartsWith("\\?\")) { return $Path }
    return "\\?\$Path"
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

$desired = @(
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project 2"; Label = "ZDH Command Center"; Color = "green" },
    @{ Path = "C:\repos\bossman"; Label = "Bossman"; Color = "yellow" },
    @{ Path = "C:\repos\Mr.SEO"; Label = "Mr.SEO"; Color = "yellow" },
    @{ Path = "C:\repos\codex-ai-systems"; Label = "Codex AI Systems"; Color = "yellow" },
    @{ Path = "C:\repos\zdhconsultingsite"; Label = "ZDH Consulting Site"; Color = "green" },
    @{ Path = "C:\repos\zdhsales"; Label = "ZDH Sales"; Color = "green" },
    @{ Path = "C:\Users\zev\Documents\Codex\2026-06-05\botox-marketplace"; Label = "Botox Marketplace"; Color = "green" },
    @{ Path = "C:\repos\Botox-Israel"; Label = "Botox Israel / THEA"; Color = "green" },
    @{ Path = "C:\repos\explainmybusiness"; Label = "ExplainMyBusiness"; Color = "green" },
    @{ Path = "C:\repos\IsraelDigitalArmy.com"; Label = "Israel Digital Army"; Color = "green" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; Label = "Israel Offshore"; Color = "green" },
    @{ Path = "C:\repos\webdesignisrael"; Label = "Web Design Israel"; Color = "green" },
    @{ Path = "C:\repos\book"; Label = "zdhbook"; Color = "green" },
    @{ Path = "C:\repos\EnglishComedyTLV"; Label = "EnglishComedyTLV"; Color = "yellow" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project"; Label = "Comedy website project"; Color = "green" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\zevhecht.com"; Label = "Zev Hecht"; Color = "green" }
)

$threadAssignments = @(
    @{ Id = "019ea0a7-1056-7c00-84f1-12fa689e503c"; Path = "C:\repos\bossman"; Label = "Bossman" },
    @{ Id = "019eaaf1-a97f-7172-ab4d-25a7d433d659"; Path = "C:\repos\Mr.SEO"; Label = "Mr.SEO" },
    @{ Id = "019e9f8f-7f6d-7691-8761-9b0519c35585"; Path = "C:\repos\zdhsales"; Label = "ZDH Sales" },
    @{ Id = "019e9f90-0538-7562-b162-ae6a9b802239"; Path = "C:\repos\webdesignisrael"; Label = "Web Design Israel" },
    @{ Id = "019ea101-a815-7c53-b267-690028a4f137"; Path = "C:\repos\explainmybusiness"; Label = "ExplainMyBusiness" },
    @{ Id = "019ea9e3-fc7b-71c3-87ad-f984cb9e55fd"; Path = "C:\repos\IsraelDigitalArmy.com"; Label = "Israel Digital Army" },
    @{ Id = "019eaa12-5d38-7d22-9b85-c8a7d34404ba"; Path = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; Label = "Israel Offshore" },
    @{ Id = "019eb30e-9405-7690-9b47-e4e9f4b2a704"; Path = "C:\repos\book"; Label = "zdhbook" }
)

$existing = @($desired | Where-Object { Test-Path -LiteralPath $_.Path })
$roots = @($existing | ForEach-Object { $_.Path })
$backup = "$StatePath.bak-project-containers-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $StatePath -Destination $backup -Force

$state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
$validThreadAssignments = @($threadAssignments | Where-Object { Test-Path -LiteralPath $_.Path })

$hintsProperty = $state.PSObject.Properties["thread-workspace-root-hints"]
if (-not $hintsProperty) {
    $state | Add-Member -NotePropertyName "thread-workspace-root-hints" -NotePropertyValue ([pscustomobject]@{})
}
$hints = $state.PSObject.Properties["thread-workspace-root-hints"].Value
foreach ($assignment in $validThreadAssignments) {
    $hints | Add-Member -NotePropertyName $assignment.Id -NotePropertyValue $assignment.Path -Force
}

$state.'electron-saved-workspace-roots' = @($roots)
$state.'project-order' = @($roots + @("cloud:zdhconsulting/mission-control"))

$labels = [pscustomobject]@{}
foreach ($item in $existing) {
    $labels | Add-Member -NotePropertyName $item.Path -NotePropertyValue $item.Label
}
$state.'electron-workspace-root-labels' = $labels

$appearances = [pscustomobject]@{}
foreach ($item in $existing) {
    $value = [pscustomobject]@{
        color = $item.Color
        marker = [pscustomobject]@{ kind = "icon"; icon = "folder" }
    }
    $appearances | Add-Member -NotePropertyName $item.Path -NotePropertyValue $value
}
$state.'project-appearances' = $appearances
$state.'pinned-thread-ids' = @(
    "019ec3de-d9cd-70e1-a8b6-6f71f1da16d4",
    "019ea0a7-1056-7c00-84f1-12fa689e503c"
)

$atom = $state.PSObject.Properties["electron-persisted-atom-state"].Value
if ($atom) {
    foreach ($name in @(
        "electron-saved-workspace-roots",
        "project-order",
        "active-workspace-roots",
        "electron-workspace-root-labels",
        "project-appearances",
        "pinned-thread-ids"
    )) {
        Remove-PropertyIfPresent -Object $atom -Name $name
    }
}

Write-Utf8NoBomFile -Path $StatePath -Text ($state | ConvertTo-Json -Depth 100 -Compress)

$threadPatch = [pscustomobject]@{
    skipped = $true
    reason = ""
    backup = $null
    updated = 0
    changes = @()
}

if ($NoPatchThreadAssignments) {
    $threadPatch.reason = "NoPatchThreadAssignments"
} elseif (-not (Test-Path -LiteralPath $ThreadsDbPath)) {
    $threadPatch.reason = "ThreadsDbPath not found: $ThreadsDbPath"
} elseif ($validThreadAssignments.Count -eq 0) {
    $threadPatch.reason = "No valid thread assignment targets found"
} elseif (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    $threadPatch.reason = "python not found"
} elseif (@(Get-CodexDesktopProcess).Count -gt 0) {
    $threadPatch.reason = "Codex Desktop is running; thread assignment patch is only safe through codex-project-containers-after-exit.cmd"
} else {
    $threadPatch.skipped = $false
    $threadPatch.reason = "patched"
    $threadPatch.backup = "$ThreadsDbPath.bak-project-containers-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $ThreadsDbPath -Destination $threadPatch.backup -Force

    $assignmentPayload = @($validThreadAssignments | ForEach-Object {
        [pscustomobject]@{
            id = $_.Id
            cwd = Get-ExtendedWindowsPath -Path $_.Path
            label = $_.Label
        }
    })

    $assignmentPath = Join-Path $env:TEMP "codex-project-thread-assignments.json"
    $patcherPath = Join-Path $env:TEMP "codex-project-thread-assignments.py"
    Write-Utf8NoBomFile -Path $assignmentPath -Text ($assignmentPayload | ConvertTo-Json -Depth 5)
    Write-Utf8NoBomFile -Path $patcherPath -Text @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
assignment_path = sys.argv[2]

with open(assignment_path, "r", encoding="utf-8-sig") as handle:
    assignments = json.load(handle)

connection = sqlite3.connect(db_path)
cursor = connection.cursor()
changes = []
updated = 0

for assignment in assignments:
    row = cursor.execute(
        "select cwd, title from threads where id = ?",
        (assignment["id"],),
    ).fetchone()
    if not row:
        changes.append({
            "id": assignment["id"],
            "label": assignment["label"],
            "status": "missing",
        })
        continue

    old_cwd, title = row
    new_cwd = assignment["cwd"]
    status = "unchanged"
    if old_cwd != new_cwd:
        cursor.execute(
            "update threads set cwd = ? where id = ?",
            (new_cwd, assignment["id"]),
        )
        updated += cursor.rowcount
        status = "updated"

    changes.append({
        "id": assignment["id"],
        "label": assignment["label"],
        "status": status,
        "old_cwd": old_cwd,
        "new_cwd": new_cwd,
        "title": title,
    })

connection.commit()
connection.close()

print(json.dumps({
    "updated": updated,
    "changes": changes,
}, ensure_ascii=False))
'@

    $patchOutput = & python $patcherPath $ThreadsDbPath $assignmentPath
    $patchResult = $patchOutput | ConvertFrom-Json
    $threadPatch.updated = $patchResult.updated
    $threadPatch.changes = @($patchResult.changes)
    Remove-Item -LiteralPath $assignmentPath, $patcherPath -Force -ErrorAction SilentlyContinue
}

$result = [pscustomobject]@{
    statePath = $StatePath
    backup = $backup
    savedRootCount = $roots.Count
    savedRoots = $roots
    threadAssignments = $threadPatch
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    "Applied $($roots.Count) Codex project containers."
    "Backup: $backup"
    foreach ($root in $roots) {
        " - $root"
    }
}
