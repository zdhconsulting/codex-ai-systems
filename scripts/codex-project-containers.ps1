param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [switch] $Json
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$StatePath = if ($StatePath) { $StatePath } else { Join-Path $CodexHome ".codex-global-state.json" }

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

if (-not (Test-Path -LiteralPath $StatePath)) {
    throw "State file not found: $StatePath"
}

$desired = @(
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project 2"; Label = "ZDH Command Center"; Color = "green" },
    @{ Path = "C:\Repos\bossman"; Label = "Bossman"; Color = "yellow" },
    @{ Path = "C:\Repos\codex-ai-systems"; Label = "Codex AI Systems"; Color = "yellow" },
    @{ Path = "C:\repos\zdhconsultingsite"; Label = "ZDH Consulting Site"; Color = "green" },
    @{ Path = "C:\Repos\zdhsales"; Label = "ZDH Sales"; Color = "green" },
    @{ Path = "C:\Users\zev\Documents\Codex\2026-06-05\botox-marketplace"; Label = "Botox Marketplace"; Color = "green" },
    @{ Path = "C:\Repos\Botox-Israel"; Label = "Botox Israel / THEA"; Color = "green" },
    @{ Path = "C:\Repos\explainmybusiness"; Label = "ExplainMyBusiness"; Color = "green" },
    @{ Path = "C:\Repos\IsraelDigitalArmy.com"; Label = "Israel Digital Army"; Color = "green" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\IsraelOffshore"; Label = "Israel Offshore"; Color = "green" },
    @{ Path = "C:\Repos\webdesignisrael"; Label = "Web Design Israel"; Color = "green" },
    @{ Path = "C:\Repos\book"; Label = "zdhbook"; Color = "green" },
    @{ Path = "C:\repos\EnglishComedyTLV"; Label = "EnglishComedyTLV"; Color = "yellow" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\New project"; Label = "Comedy website project"; Color = "green" },
    @{ Path = "C:\Users\zev\OneDrive\Documents\zevhecht.com"; Label = "Zev Hecht"; Color = "green" }
)

$existing = @($desired | Where-Object { Test-Path -LiteralPath $_.Path })
$roots = @($existing | ForEach-Object { $_.Path })
$backup = "$StatePath.bak-project-containers-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $StatePath -Destination $backup -Force

$state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
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

$result = [pscustomobject]@{
    statePath = $StatePath
    backup = $backup
    savedRootCount = $roots.Count
    savedRoots = $roots
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
