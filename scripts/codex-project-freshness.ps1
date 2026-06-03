param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string[]] $ProjectPath = @(),
    [switch] $NoUpdateLabels,
    [switch] $Json,
    [switch] $Quiet,
    [int] $MaxFilesPerProject = 30000
)

$ErrorActionPreference = "Stop"
$CodexHome = if ($CodexHome) { $CodexHome } else { Split-Path -Parent $PSScriptRoot }
$StatePath = if ($StatePath) { $StatePath } else { Join-Path $CodexHome ".codex-global-state.json" }
$configPath = Join-Path $CodexHome "config.toml"
$cachePath = Join-Path $CodexHome "project-freshness-state.json"

function Normalize-ProjectPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    if ($Path.StartsWith("cloud:", [System.StringComparison]::OrdinalIgnoreCase)) { return "" }
    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd("\")
    } catch {
        return ""
    }
}

function Get-StateObject {
    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
    $raw = Get-Content -LiteralPath $StatePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function ConvertTo-JsonObjectText {
    param([hashtable] $Map)

    $ordered = [ordered]@{}
    foreach ($key in ($Map.Keys | Sort-Object)) {
        $ordered[$key] = $Map[$key]
    }
    return ($ordered | ConvertTo-Json -Depth 5 -Compress)
}

function Set-WorkspaceLabelsInState {
    param(
        [string] $Path,
        [hashtable] $Labels
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $labelsJson = ConvertTo-JsonObjectText -Map $Labels
    $backup = "$Path.bak-project-freshness-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force

    $labelPattern = '"electron-workspace-root-labels"\s*:\s*\{[^{}]*\}'
    if ([regex]::IsMatch($raw, $labelPattern)) {
        $updated = [regex]::Replace($raw, $labelPattern, '"electron-workspace-root-labels":' + $labelsJson, 1)
    } else {
        $atomPattern = '"electron-persisted-atom-state"\s*:\s*\{'
        if (-not [regex]::IsMatch($raw, $atomPattern)) {
            throw "Cannot find electron-persisted-atom-state in $Path"
        }
        $updated = [regex]::Replace($raw, $atomPattern, '$0"electron-workspace-root-labels":' + $labelsJson + ',', 1)
    }

    Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
    return $backup
}

function Get-WorkspaceLabelsFromRawState {
    param([string] $Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    $raw = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($raw, '"electron-workspace-root-labels"\s*:\s*(\{[^{}]*\})')
    if (-not $match.Success) { return $map }

    try {
        $labelsObject = $match.Groups[1].Value | ConvertFrom-Json
        foreach ($property in $labelsObject.PSObject.Properties) {
            $map[$property.Name] = [string]$property.Value
        }
    } catch {
        return @{}
    }

    return $map
}

function Get-ProjectRoots {
    param($State)

    $seen = @{}
    $roots = New-Object System.Collections.Generic.List[string]

    function Add-Root {
        param([string] $Candidate)
        $normalized = Normalize-ProjectPath $Candidate
        if (-not $normalized) { return }
        if (-not (Test-Path -LiteralPath $normalized)) { return }
        $key = $normalized.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $roots.Add($normalized)
        }
    }

    foreach ($path in $ProjectPath) { Add-Root $path }

    if ($State) {
        $atom = $State.'electron-persisted-atom-state'
        if ($atom) {
            foreach ($path in @($atom.'electron-saved-workspace-roots')) { Add-Root $path }
            foreach ($path in @($atom.'active-workspace-roots')) { Add-Root $path }
            foreach ($path in @($atom.'project-order')) { Add-Root $path }
        }
    }

    if (Test-Path -LiteralPath $configPath) {
        $configText = Get-Content -LiteralPath $configPath -Raw
        $matches = [regex]::Matches($configText, "\[projects\.'([^']+)'\]")
        foreach ($match in $matches) { Add-Root $match.Groups[1].Value }
    }

    return @($roots)
}

function Get-LatestProjectWrite {
    param([string] $Root)

    $ignore = @{
        ".git" = $true; "node_modules" = $true; ".next" = $true; "dist" = $true; "build" = $true
        "out" = $true; ".cache" = $true; ".turbo" = $true; ".vercel" = $true; "coverage" = $true
        "vendor" = $true; "target" = $true; "bin" = $true; "obj" = $true; ".venv" = $true
        "__pycache__" = $true; ".pytest_cache" = $true
    }

    $rootItem = Get-Item -LiteralPath $Root -Force
    $latest = $rootItem.LastWriteTime
    $scanned = 0
    $dirs = New-Object System.Collections.Generic.Queue[string]
    $dirs.Enqueue($Root)

    while ($dirs.Count -gt 0 -and $scanned -lt $MaxFilesPerProject) {
        $dir = $dirs.Dequeue()
        $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if ($scanned -ge $MaxFilesPerProject) { break }
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($child.PSIsContainer) {
                if (-not $ignore.ContainsKey($child.Name.ToLowerInvariant())) {
                    if ($child.LastWriteTime -gt $latest) { $latest = $child.LastWriteTime }
                    $dirs.Enqueue($child.FullName)
                }
            } else {
                $scanned++
                if ($child.LastWriteTime -gt $latest) { $latest = $child.LastWriteTime }
            }
        }
    }

    return [pscustomobject]@{
        LastModified = $latest
        FilesScanned = $scanned
        HitLimit = ($scanned -ge $MaxFilesPerProject)
    }
}

function Get-FreshnessBand {
    param([timespan] $Age)

    if ($Age.TotalHours -le 24) {
        return [pscustomobject]@{ Name = "fresh"; Label = "FRESH"; Ansi = "32"; Icon = [char]::ConvertFromUtf32(0x1F7E2) }
    }
    if ($Age.TotalDays -le 3) {
        return [pscustomobject]@{ Name = "warm"; Label = "WARM"; Ansi = "33"; Icon = [char]::ConvertFromUtf32(0x1F7E1) }
    }
    if ($Age.TotalDays -le 7) {
        return [pscustomobject]@{ Name = "aging"; Label = "AGING"; Ansi = "38;5;208"; Icon = [char]::ConvertFromUtf32(0x1F7E0) }
    }
    if ($Age.TotalDays -le 14) {
        return [pscustomobject]@{ Name = "stale"; Label = "STALE"; Ansi = "31"; Icon = [char]::ConvertFromUtf32(0x1F534) }
    }
    return [pscustomobject]@{ Name = "dormant"; Label = "DORMANT"; Ansi = "90"; Icon = [char]::ConvertFromUtf32(0x26AB) }
}

function Strip-FreshnessPrefix {
    param([string] $Label)
    if (-not $Label) { return "" }
    $icons = @(
        [char]::ConvertFromUtf32(0x1F7E2),
        [char]::ConvertFromUtf32(0x1F7E1),
        [char]::ConvertFromUtf32(0x1F7E0),
        [char]::ConvertFromUtf32(0x1F534),
        [char]::ConvertFromUtf32(0x26AB)
    )
    foreach ($icon in $icons) {
        if ($Label.StartsWith("$icon ")) {
            return $Label.Substring($icon.Length + 1)
        }
    }
    return ($Label -replace '^\[(FRESH|WARM|AGING|STALE|DORMANT)\]\s+', '')
}

$state = Get-StateObject
$roots = Get-ProjectRoots -State $state
$now = Get-Date
$results = foreach ($root in $roots) {
    $write = Get-LatestProjectWrite -Root $root
    $age = $now - $write.LastModified
    $band = Get-FreshnessBand -Age $age
    [pscustomobject]@{
        Path = $root
        Name = Split-Path -Leaf $root
        LastModified = $write.LastModified.ToString("s")
        AgeDays = [math]::Round($age.TotalDays, 2)
        Status = $band.Name
        Label = $band.Label
        Icon = $band.Icon
        Ansi = $band.Ansi
        FilesScanned = $write.FilesScanned
        HitLimit = $write.HitLimit
    }
}

if (-not $NoUpdateLabels -and (Test-Path -LiteralPath $StatePath) -and $results.Count -gt 0) {
        $labelMap = Get-WorkspaceLabelsFromRawState -Path $StatePath

        if (Test-Path -LiteralPath $cachePath) {
            $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        } else {
            $cache = [pscustomobject]@{ originalLabels = [pscustomobject]@{} }
        }
        if (-not $cache.originalLabels) {
            $cache | Add-Member -NotePropertyName "originalLabels" -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        foreach ($project in $results) {
            $path = $project.Path
            $current = if ($labelMap.ContainsKey($path)) { $labelMap[$path] } else { "" }
            $original = $cache.originalLabels.$path
            if (-not $original) {
                $base = if ($current) { Strip-FreshnessPrefix $current } else { $project.Name }
                $cache.originalLabels | Add-Member -NotePropertyName $path -NotePropertyValue $base -Force
                $original = $base
            }
            $newLabel = "$($project.Icon) $original"
            $labelMap[$path] = $newLabel
        }

        $backup = Set-WorkspaceLabelsInState -Path $StatePath -Labels $labelMap

        $cacheOut = [pscustomobject]@{
            lastRun = (Get-Date).ToString("s")
            stateBackup = $backup
            originalLabels = $cache.originalLabels
            projects = $results
        }
        $cacheOut | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cachePath -Encoding UTF8
}

if ($Json) {
    $results | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $Quiet) {
    $esc = [char]27
    foreach ($project in ($results | Sort-Object AgeDays)) {
        $ageText = if ($project.AgeDays -eq 0) { "<1d" } else { "$($project.AgeDays)d" }
        Write-Host "$esc[$($project.Ansi)m[$($project.Label)]$esc[0m $ageText $($project.Path)"
    }
}
