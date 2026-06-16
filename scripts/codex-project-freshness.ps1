param(
    [string] $CodexHome = "",
    [string] $StatePath = "",
    [string[]] $ProjectPath = @(),
    [switch] $NoUpdateLabels,
    [switch] $NoUpdateAppearances,
    [switch] $IncludeTrustedProjects,
    [switch] $PatchLabels,
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

function Write-Utf8NoBomFile {
    param(
        [string] $Path,
        [string] $Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Find-JsonPropertyRange {
    param(
        [string] $Text,
        [string] $PropertyName
    )

    $propertyPattern = '"' + [regex]::Escape($PropertyName) + '"\s*:'
    $match = [regex]::Match($Text, $propertyPattern)
    if (-not $match.Success) { return $null }

    $valueStart = $match.Index + $match.Length
    while ($valueStart -lt $Text.Length -and [char]::IsWhiteSpace($Text[$valueStart])) {
        $valueStart++
    }
    if ($valueStart -ge $Text.Length -or $Text[$valueStart] -ne "{") {
        throw "Property '$PropertyName' is not a JSON object."
    }

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $valueStart; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq "\") {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
        } elseif ($ch -eq "{") {
            $depth++
        } elseif ($ch -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{
                    PropertyStart = $match.Index
                    PropertyLength = ($i + 1) - $match.Index
                    ValueStart = $valueStart
                    ValueLength = ($i + 1) - $valueStart
                    ValueText = $Text.Substring($valueStart, ($i + 1) - $valueStart)
                }
            }
        }
    }

    throw "Could not find the end of property '$PropertyName'."
}

function Get-JsonObjectMapFromState {
    param(
        [string] $Path,
        [string] $PropertyName
    )

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    $raw = Get-Content -LiteralPath $Path -Raw
    $range = Find-JsonPropertyRange -Text $raw -PropertyName $PropertyName
    if (-not $range) { return $map }

    try {
        $object = $range.ValueText | ConvertFrom-Json
        foreach ($property in $object.PSObject.Properties) {
            $map[$property.Name] = $property.Value
        }
    } catch {
        return @{}
    }

    return $map
}

function Get-RootJsonObjectMapFromState {
    param(
        [string] $Path,
        [string] $PropertyName
    )

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    try {
        $stateObject = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $property = $stateObject.PSObject.Properties[$PropertyName]
        if (-not $property) { return $map }
        foreach ($child in $property.Value.PSObject.Properties) {
            $map[$child.Name] = $child.Value
        }
    } catch {
        return @{}
    }

    return $map
}

function Set-RootJsonObjectPropertyInState {
    param(
        [string] $Path,
        [string] $PropertyName,
        [hashtable] $Map
    )

    $backup = "$Path.bak-project-freshness-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force

    $stateObject = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $ordered = [ordered]@{}
    foreach ($key in ($Map.Keys | Sort-Object)) {
        $ordered[$key] = $Map[$key]
    }

    $existing = $stateObject.PSObject.Properties[$PropertyName]
    if ($existing) {
        $stateObject.PSObject.Properties.Remove($PropertyName)
    }
    $stateObject | Add-Member -NotePropertyName $PropertyName -NotePropertyValue ([pscustomobject]$ordered) -Force

    $atom = $stateObject.PSObject.Properties["electron-persisted-atom-state"].Value
    if ($atom -and $atom.PSObject.Properties[$PropertyName]) {
        $atom.PSObject.Properties.Remove($PropertyName)
    }

    Write-Utf8NoBomFile -Path $Path -Text ($stateObject | ConvertTo-Json -Depth 100 -Compress)
    return $backup
}

function Set-JsonObjectPropertyInState {
    param(
        [string] $Path,
        [string] $PropertyName,
        [hashtable] $Map
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $propertyJson = '"' + $PropertyName + '":' + (ConvertTo-JsonObjectText -Map $Map)
    $backup = "$Path.bak-project-freshness-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force

    $range = Find-JsonPropertyRange -Text $raw -PropertyName $PropertyName
    if ($range) {
        $updated = $raw.Substring(0, $range.PropertyStart) + $propertyJson + $raw.Substring($range.PropertyStart + $range.PropertyLength)
    } else {
        $atomPattern = '"electron-persisted-atom-state"\s*:\s*\{'
        if (-not [regex]::IsMatch($raw, $atomPattern)) {
            throw "Cannot find electron-persisted-atom-state in $Path"
        }
        $updated = [regex]::Replace($raw, $atomPattern, '$0' + $propertyJson + ',', 1)
    }

    Write-Utf8NoBomFile -Path $Path -Text $updated
    return $backup
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

    Write-Utf8NoBomFile -Path $Path -Text $updated
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

function Get-CanonicalProjectPathMap {
    param($State)

    $map = @{}
    function Add-CanonicalPath {
        param([string] $Candidate)
        $normalized = Normalize-ProjectPath $Candidate
        if (-not $normalized) { return }
        $map[$normalized.ToLowerInvariant()] = $normalized
    }

    if ($State) {
        foreach ($path in @($State.'electron-saved-workspace-roots')) { Add-CanonicalPath $path }
        foreach ($path in @($State.'active-workspace-roots')) { Add-CanonicalPath $path }
        foreach ($path in @($State.'project-order')) { Add-CanonicalPath $path }

        $atom = $State.'electron-persisted-atom-state'
        if ($atom) {
            foreach ($path in @($atom.'electron-saved-workspace-roots')) { Add-CanonicalPath $path }
            foreach ($path in @($atom.'active-workspace-roots')) { Add-CanonicalPath $path }
            foreach ($path in @($atom.'project-order')) { Add-CanonicalPath $path }
        }
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
        foreach ($path in @($State.'electron-saved-workspace-roots')) { Add-Root $path }
        foreach ($path in @($State.'active-workspace-roots')) { Add-Root $path }
        foreach ($path in @($State.'project-order')) { Add-Root $path }

        $atom = $State.'electron-persisted-atom-state'
        if ($atom) {
            foreach ($path in @($atom.'electron-saved-workspace-roots')) { Add-Root $path }
            foreach ($path in @($atom.'active-workspace-roots')) { Add-Root $path }
            foreach ($path in @($atom.'project-order')) { Add-Root $path }
        }
    }

    if ($IncludeTrustedProjects -and (Test-Path -LiteralPath $configPath)) {
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

    if ($Age.TotalHours -le 12) {
        return [pscustomobject]@{ Name = "fresh"; Label = "LIVE"; Ansi = "32"; Icon = [char]::ConvertFromUtf32(0x1F7E2) }
    }
    if ($Age.TotalHours -le 24) {
        return [pscustomobject]@{ Name = "warm"; Label = "DUE"; Ansi = "33"; Icon = [char]::ConvertFromUtf32(0x1F7E1) }
    }
    if ($Age.TotalHours -le 36) {
        return [pscustomobject]@{ Name = "aging"; Label = "SOON"; Ansi = "38;5;208"; Icon = [char]::ConvertFromUtf32(0x1F7E0) }
    }
    if ($Age.TotalHours -le 48) {
        return [pscustomobject]@{ Name = "stale"; Label = "HOT"; Ansi = "31"; Icon = [char]::ConvertFromUtf32(0x1F534) }
    }
    return [pscustomobject]@{ Name = "dormant"; Label = "COLD"; Ansi = "90"; Icon = [char]::ConvertFromUtf32(0x26AB) }
}

function Get-CodexAppearanceColor {
    param([string] $Status)

    switch ($Status) {
        "fresh" { return "green" }
        "warm" { return "yellow" }
        "aging" { return "orange" }
        "stale" { return "red" }
        default { return "black" }
    }
}

function Get-CockpitProjectOverride {
    param([string] $Path)

    $normalized = (Normalize-ProjectPath $Path).ToLowerInvariant()
    switch ($normalized) {
        "c:\users\zev\onedrive\documents\new project 2" { return [pscustomobject]@{ Badge = "OPS"; Color = "blue" } }
        "c:\repos\bossman" { return [pscustomobject]@{ Badge = "SYS"; Color = "blue" } }
        "c:\repos\codex-ai-systems" { return [pscustomobject]@{ Badge = "SYS"; Color = "blue" } }
        "c:\repos\mr.seo" { return [pscustomobject]@{ Badge = "SYS"; Color = "blue" } }
        "c:\repos\englishcomedytlv" { return [pscustomobject]@{ Badge = "QA"; Color = "black" } }
        "c:\repos\book" { return [pscustomobject]@{ Badge = "HOLD"; Color = "black" } }
        "c:\users\zev\onedrive\documents\new project" { return [pscustomobject]@{ Badge = "PARK"; Color = "black" } }
        default { return $null }
    }
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
    return ($Label -replace '^\[(FRESH|WARM|AGING|STALE|DORMANT|OPS|SYS|LIVE|DUE|SOON|HOT|COLD|HOLD|QA|PARK)\]\s+', '')
}

$state = Get-StateObject
$canonicalProjectPaths = Get-CanonicalProjectPathMap -State $state
$roots = Get-ProjectRoots -State $state
$now = Get-Date
$results = foreach ($root in $roots) {
    $write = Get-LatestProjectWrite -Root $root
    $age = $now - $write.LastModified
    $band = Get-FreshnessBand -Age $age
    $canonicalRoot = if ($canonicalProjectPaths.ContainsKey($root.ToLowerInvariant())) { $canonicalProjectPaths[$root.ToLowerInvariant()] } else { $root }
    $cockpitOverride = Get-CockpitProjectOverride -Path $canonicalRoot
    $displayLabel = if ($cockpitOverride) { $cockpitOverride.Badge } else { $band.Label }
    $appearanceColor = if ($cockpitOverride) { $cockpitOverride.Color } else { Get-CodexAppearanceColor -Status $band.Name }
    [pscustomobject]@{
        Path = $canonicalRoot
        Name = Split-Path -Leaf $root
        LastModified = $write.LastModified.ToString("s")
        AgeHours = [math]::Round($age.TotalHours, 1)
        AgeDays = [math]::Round($age.TotalDays, 2)
        Status = $band.Name
        Label = $displayLabel
        Icon = $band.Icon
        Ansi = $band.Ansi
        CodexAppearanceColor = $appearanceColor
        FilesScanned = $write.FilesScanned
        HitLimit = $write.HitLimit
    }
}

if (-not $NoUpdateAppearances -and -not $NoUpdateLabels -and (Test-Path -LiteralPath $StatePath) -and $results.Count -gt 0) {
        $appearanceMap = Get-RootJsonObjectMapFromState -Path $StatePath -PropertyName "project-appearances"

        foreach ($project in $results) {
            $path = $project.Path
            $existing = if ($appearanceMap.ContainsKey($path)) { $appearanceMap[$path] } else { $null }
            $marker = $null
            if ($existing -and $existing.marker) {
                $marker = $existing.marker
            } else {
                $marker = [ordered]@{ kind = "icon"; icon = "folder" }
            }
            $appearanceMap[$path] = [ordered]@{
                color = $project.CodexAppearanceColor
                marker = $marker
            }
        }

        $appearanceBackup = Set-RootJsonObjectPropertyInState -Path $StatePath -PropertyName "project-appearances" -Map $appearanceMap

        $cacheOut = [pscustomobject]@{
            lastRun = (Get-Date).ToString("s")
            appearanceStateBackup = $appearanceBackup
            appearanceUpdated = $true
            labelPatchEnabled = $false
            projects = $results
        }
        Write-Utf8NoBomFile -Path $cachePath -Text ($cacheOut | ConvertTo-Json -Depth 20)
}

if ($PatchLabels -and -not $NoUpdateLabels -and (Test-Path -LiteralPath $StatePath) -and $results.Count -gt 0) {
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
            $newLabel = "[$($project.Label)] $original"
            $labelMap[$path] = $newLabel
        }

        $backup = Set-WorkspaceLabelsInState -Path $StatePath -Labels $labelMap

        $cacheOut = [pscustomobject]@{
            lastRun = (Get-Date).ToString("s")
            stateBackup = $backup
            originalLabels = $cache.originalLabels
            projects = $results
        }
        Write-Utf8NoBomFile -Path $cachePath -Text ($cacheOut | ConvertTo-Json -Depth 20)
}

if ($Json) {
    $results | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $Quiet) {
    $esc = [char]27
    foreach ($project in ($results | Sort-Object AgeDays)) {
        $ageText = if ($project.AgeHours -lt 1) { "<1h" } elseif ($project.AgeHours -lt 48) { "$($project.AgeHours)h" } else { "$($project.AgeDays)d" }
        Write-Host "$esc[$($project.Ansi)m[$($project.Label)]$esc[0m $ageText $($project.Path)"
    }
}
