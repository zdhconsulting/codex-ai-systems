param(
    [string] $CodexHome = (Join-Path $env:USERPROFILE ".codex"),
    [string[]] $Pack = @("All"),
    [switch] $ListPacks
)

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packManifestPath = Join-Path $repoRoot "packs\manifest.json"

function Get-RequestedPackNames {
    param([string[]] $PackNames)

    @($PackNames | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-PackManifest {
    if (-not (Test-Path -LiteralPath $packManifestPath)) {
        return $null
    }
    return (Get-Content -LiteralPath $packManifestPath -Raw | ConvertFrom-Json)
}

$packManifest = Get-PackManifest
if ($ListPacks) {
    if (-not $packManifest) {
        Write-Error "Pack manifest not found: $packManifestPath"
        exit 1
    }

    Write-Host "Available Codex AI Systems packs:"
    foreach ($item in @($packManifest.packs)) {
        Write-Host ("- {0}: {1}" -f $item.id, $item.name)
        Write-Host ("  {0}" -f $item.description)
    }
    exit 0
}

New-Item -ItemType Directory -Force `
    $CodexHome, `
    (Join-Path $CodexHome "scripts"), `
    (Join-Path $CodexHome "queues"), `
    (Join-Path $CodexHome "skills") | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot "instructions\AGENTS.md") `
    -Destination (Join-Path $CodexHome "AGENTS.md") -Force

Copy-Item -Path (Join-Path $repoRoot "scripts\*") `
    -Destination (Join-Path $CodexHome "scripts") -Force

Copy-Item -Path (Join-Path $repoRoot "profiles\*.config.toml") `
    -Destination $CodexHome -Force

$configPath = Join-Path $CodexHome "config.toml"
$notifyPath = Join-Path $CodexHome "scripts\codex-notify-router.cmd"
$notifyLine = 'notify = [ "' + ($notifyPath -replace '\\', '\\') + '", "turn-ended" ]'
if (Test-Path -LiteralPath $configPath) {
    $configText = Get-Content -LiteralPath $configPath -Raw
    if ($configText -match '(?m)^notify\s*=') {
        $configText = [regex]::Replace($configText, '(?m)^notify\s*=.*$', $notifyLine, 1)
    } else {
        $configText = $notifyLine + "`r`n" + $configText
    }
    Set-Content -LiteralPath $configPath -Value $configText -Encoding UTF8
} else {
    Set-Content -LiteralPath $configPath -Value ($notifyLine + "`r`n") -Encoding UTF8
}

$skillSource = Join-Path $repoRoot "skills"
$skillDirs = @(Get-ChildItem -LiteralPath $skillSource -Directory)
$requestedPacks = Get-RequestedPackNames -PackNames $Pack
$installAllSkills = $requestedPacks.Count -eq 0 -or ($requestedPacks | Where-Object { $_ -ieq "All" }).Count -gt 0
$selectedSkillNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$installedPackNames = New-Object System.Collections.Generic.List[string]

if ($installAllSkills -or -not $packManifest) {
    foreach ($skill in $skillDirs) {
        [void] $selectedSkillNames.Add($skill.Name)
    }
    $installedPackNames.Add("All")
} else {
    $packLookup = @{}
    foreach ($item in @($packManifest.packs)) {
        $packLookup[[string]$item.id] = $item
    }

    $expandedPacks = [System.Collections.Generic.List[string]]::new()
    if (($requestedPacks | Where-Object { $_ -ieq "Core" }).Count -eq 0) {
        $expandedPacks.Add("Core")
    }
    foreach ($name in $requestedPacks) {
        $expandedPacks.Add($name)
    }

    foreach ($packName in $expandedPacks) {
        $match = $packLookup.Keys | Where-Object { $_ -ieq $packName } | Select-Object -First 1
        if (-not $match) {
            Write-Error "Unknown pack '$packName'. Run .\install.ps1 -ListPacks to see available packs."
            exit 1
        }

        $packItem = $packLookup[$match]
        $installedPackNames.Add($packItem.id)
        foreach ($skillName in @($packItem.skills)) {
            if ($skillName) {
                [void] $selectedSkillNames.Add([string]$skillName)
            }
        }
    }
}

foreach ($skillName in $selectedSkillNames) {
    $source = Join-Path $skillSource $skillName
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Pack references missing skill: $skillName"
        continue
    }
    $dest = Join-Path $CodexHome ("skills\" + $skillName)
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $dest -Recurse -Force
}

$queuePath = Join-Path $CodexHome "queues\owner-buttons.json"
if (-not (Test-Path $queuePath)) {
    "[]" | Set-Content -Path $queuePath -Encoding UTF8
}

Write-Host "Installed Codex AI Systems to: $CodexHome"
Write-Host "Installed packs: $($installedPackNames -join ', ')"
Write-Host "Installed skill count: $($selectedSkillNames.Count)"
Write-Host "Installed reusable skills from: $(Join-Path $repoRoot "skills")"
Write-Host "Owner button queue: $queuePath"
Write-Host "Run this to verify:"
Write-Host "$CodexHome\scripts\git-guard.cmd"
Write-Host "$CodexHome\scripts\codex-doctor.cmd"
Write-Host "$CodexHome\scripts\codex-gear-test.cmd"
Write-Host "$CodexHome\scripts\codex-systems-status.cmd"
Write-Host "$CodexHome\scripts\codex-project-rules.cmd"
Write-Host "$CodexHome\scripts\codex-project-freshness.cmd"
