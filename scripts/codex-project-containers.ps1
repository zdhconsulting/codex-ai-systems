param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string] $ThreadsDbPath = "",
    [switch] $NoPatchThreadAssignments,
    [switch] $Json,
    [ValidateRange(1, 20)]
    [int] $MaxStateBackups = 2,
    [ValidateRange(1, 2048)]
    [int] $MaxStateFileMB = 256
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$StatePath = if ($StatePath) { $StatePath } else { Join-Path $CodexHome ".codex-global-state.json" }
$ThreadsDbPath = if ($ThreadsDbPath) {
    $ThreadsDbPath
} elseif (Test-Path -LiteralPath (Join-Path $CodexHome "state_5.sqlite")) {
    Join-Path $CodexHome "state_5.sqlite"
} else {
    Join-Path $CodexHome "sqlite\state_5.sqlite"
}

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

function Set-NoteProperty {
    param(
        [object] $Object,
        [string] $Name,
        [object] $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
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

function Remove-OldStateBackups {
    param([int] $Keep)

    $stateDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $StatePath))
    $stateFileName = Split-Path -Leaf $StatePath
    $backupPrefix = "$stateFileName.bak-project-containers-"
    $backups = @(Get-ChildItem -LiteralPath $stateDirectory -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object Name -Descending)
    $toRemove = if ($Keep -le 0) { $backups } else { @($backups | Select-Object -Skip $Keep) }

    foreach ($candidate in $toRemove) {
        $candidateDirectory = [IO.Path]::GetFullPath($candidate.DirectoryName)
        if ($candidateDirectory -ne $stateDirectory -or
            -not $candidate.Name.StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected backup path: $($candidate.FullName)"
        }
        Remove-Item -LiteralPath $candidate.FullName -Force
    }
}

if (-not (Test-Path -LiteralPath $StatePath)) {
    throw "State file not found: $StatePath"
}

$desired = @(
    @{ Path = "C:\Users\zev\Documents\Codex\00-agent-chats"; Label = "00 AGENTS / Named Agent Chats"; Color = "blue" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project 2"; Label = "01 COMMAND / ZDH Center"; Color = "blue" },
    @{ Path = "C:\repos\bossman"; Label = "02 SYSTEM / Bossman Dispatch"; Color = "blue" },
    @{ Path = "C:\repos\codex-ai-systems"; Label = "03 SYSTEM / Codex OS"; Color = "blue" },
    @{ Path = "C:\repos\Mr.SEO"; Label = "04 SYSTEM / Mr.SEO"; Color = "blue" },
    @{ Path = "C:\repos\zdhsales"; Label = "10 Project  / ZDH Sales"; Color = "green" },
    @{ Path = "C:\repos\zdhconsultingsite"; Label = "11 Project / ZDH Consulting"; Color = "green" },
    @{ Path = "C:\repos\webdesignisrael"; Label = "12 Project / WebDesignIsrael"; Color = "green" },
    @{ Path = "C:\repos\explainmybusiness"; Label = "13 Project / ExplainMyBusiness"; Color = "green" },
    @{ Path = "C:\Users\zev\Documents\Codex\2026-06-05\botox-marketplace"; Label = "14 Project / Botox Marketplace"; Color = "green" },
    @{ Path = "C:\repos\Botox-Israel"; Label = "15 Project / Botox Tel Aviv | THEA"; Color = "yellow" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; Label = "16 Project / Israel Offshore"; Color = "green" },
    @{ Path = "C:\repos\IsraelDigitalArmy.com"; Label = "17 MOVEMENT / Israel Digital Army"; Color = "yellow" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\zevhecht.com"; Label = "40 Project / ZevHecht.com"; Color = "green" },
    @{ Path = "C:\repos\EnglishComedyTLV"; Label = "70 QA / EnglishComedyTLV"; Color = "black" },
    @{ Path = "C:\repos\book"; Label = "80 HOLD / zdhbook"; Color = "black" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project"; Label = "90 PARK / Comedy Site"; Color = "black" }
)

$threadAssignments = @(
    @{ Id = "019ed672-8f06-7ce1-809b-288a3ae9ddeb"; Path = "C:\repos\bossman"; Label = "Bossman" },
    @{ Id = "019eaaf1-a97f-7172-ab4d-25a7d433d659"; Path = "C:\repos\Mr.SEO"; Label = "Mr.SEO" },
    @{ Id = "019e9f8f-7f6d-7691-8761-9b0519c35585"; Path = "C:\repos\zdhsales"; Label = "ZDH Sales" },
    @{ Id = "019e9f90-0538-7562-b162-ae6a9b802239"; Path = "C:\repos\webdesignisrael"; Label = "Web Design Israel" },
    @{ Id = "019ea101-a815-7c53-b267-690028a4f137"; Path = "C:\repos\explainmybusiness"; Label = "ExplainMyBusiness" },
    @{ Id = "019ea9e3-fc7b-71c3-87ad-f984cb9e55fd"; Path = "C:\repos\IsraelDigitalArmy.com"; Label = "Israel Digital Army" },
    @{ Id = "019eaa12-5d38-7d22-9b85-c8a7d34404ba"; Path = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; Label = "Israel Offshore" },
    @{ Id = "019eb30e-9405-7690-9b47-e4e9f4b2a704"; Path = "C:\repos\book"; Label = "zdhbook" }
)

$desktopProcesses = @(Get-CodexDesktopProcess)
if ($desktopProcesses.Count -gt 0) {
    throw "Refusing to modify Codex global state while the Desktop app is running. Detected process ids: $($desktopProcesses.Id -join ', ')"
}

$existing = @($desired | Where-Object { Test-Path -LiteralPath $_.Path })
$roots = @($existing | ForEach-Object { $_.Path })
$stateInfo = Get-Item -LiteralPath $StatePath -Force
$maxStateBytes = [int64]$MaxStateFileMB * 1MB
if ($stateInfo.Length -gt $maxStateBytes) {
    throw "Refusing automatic state mutation because $StatePath is $([math]::Round($stateInfo.Length / 1MB, 1)) MB; safety limit is $MaxStateFileMB MB."
}

Remove-OldStateBackups -Keep ([math]::Max(0, $MaxStateBackups - 1))
$driveInfo = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($stateInfo.FullName))
$requiredFreeBytes = [math]::Max([int64](5GB), [int64]($stateInfo.Length * 2))
if ($driveInfo.AvailableFreeSpace -lt $requiredFreeBytes) {
    throw "Refusing state backup because only $([math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)) GB is free; at least $([math]::Round($requiredFreeBytes / 1GB, 2)) GB is required."
}

$backup = "$StatePath.bak-project-containers-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $StatePath -Destination $backup -Force
Remove-OldStateBackups -Keep $MaxStateBackups

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

Set-NoteProperty -Object $state -Name "electron-saved-workspace-roots" -Value @($roots)
Set-NoteProperty -Object $state -Name "project-order" -Value @($roots + @("cloud:zdhconsulting/mission-control"))

$labels = [pscustomobject]@{}
foreach ($item in $existing) {
    $labels | Add-Member -NotePropertyName $item.Path -NotePropertyValue $item.Label
}
Set-NoteProperty -Object $state -Name "electron-workspace-root-labels" -Value $labels

$appearances = [pscustomobject]@{}
foreach ($item in $existing) {
    $value = [pscustomobject]@{
        color = $item.Color
        marker = [pscustomobject]@{ kind = "icon"; icon = "folder" }
    }
    $appearances | Add-Member -NotePropertyName $item.Path -NotePropertyValue $value
}
Set-NoteProperty -Object $state -Name "project-appearances" -Value $appearances
$atom = $state.PSObject.Properties["electron-persisted-atom-state"].Value
if ($atom) {
    foreach ($name in @(
        "electron-saved-workspace-roots",
        "project-order",
        "active-workspace-roots",
        "electron-workspace-root-labels",
        "project-appearances"
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
