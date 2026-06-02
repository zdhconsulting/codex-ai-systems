param(
    [string] $CodexHome = (Join-Path $env:USERPROFILE ".codex"),
    [string] $SystemsRepo = "C:\Repos\codex-ai-systems",
    [string] $Task = ""
)

$ErrorActionPreference = "Continue"

function Write-Section {
    param([string] $Name)
    Write-Host ""
    Write-Host $Name
    Write-Host ("-" * $Name.Length)
}

function Invoke-GitText {
    param(
        [string[]] $GitArgs,
        [string] $WorkDir = (Get-Location).Path
    )

    $output = & git -C $WorkDir @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return (($output | Out-String).Trim())
}

$scriptRoot = Join-Path $CodexHome "scripts"
$gearModule = Join-Path $scriptRoot "CodexGear.psm1"
if (Test-Path -LiteralPath $gearModule) {
    Import-Module $gearModule -Force
}

Write-Host "Codex systems status"
Write-Host "Codex home: $CodexHome"
Write-Host "Current dir: $((Get-Location).Path)"

Write-Section "Current Git Repo"
$repoRoot = Invoke-GitText -GitArgs @("rev-parse", "--show-toplevel")
if ($repoRoot) {
    $branch = Invoke-GitText -GitArgs @("branch", "--show-current") -WorkDir $repoRoot
    $origin = Invoke-GitText -GitArgs @("remote", "get-url", "origin") -WorkDir $repoRoot
    $head = Invoke-GitText -GitArgs @("log", "-1", "--oneline") -WorkDir $repoRoot
    $dirtyText = Invoke-GitText -GitArgs @("status", "--short") -WorkDir $repoRoot
    $dirty = @($dirtyText -split "`r?`n" | Where-Object { $_ })

    Write-Host "Repo: $repoRoot"
    Write-Host "Branch: $branch"
    if ($origin) { Write-Host "Origin: $origin" } else { Write-Host "Origin: (none)" }
    Write-Host "HEAD: $head"
    Write-Host "Dirty files: $($dirty.Count)"
    foreach ($line in $dirty) { Write-Host "  $line" }
} else {
    Write-Host "Not inside a git repo."
}

Write-Section "Owner Buttons"
$ownerButton = Join-Path $scriptRoot "owner-button.cmd"
if (Test-Path -LiteralPath $ownerButton) {
    & $ownerButton list
} else {
    Write-Host "owner-button.cmd not found."
}

Write-Section "Gear Routes"
if (Test-Path -LiteralPath $gearModule) {
    $matrix = Get-CodexGearMatrix
    $matrix.Values |
        Select-Object Profile, Gear, Model, Effort, @{Name="ServiceTier";Expression={if ($_.ServiceTier) {$_.ServiceTier} else {"(default/none)"}}}, Command |
        Format-Table -AutoSize

    if ($Task) {
        $profile = Select-CodexGear -Text $Task
        $gear = Get-CodexGear -Profile $profile
        Write-Host "Task route: $Task"
        Write-Host "Selected: $($gear.Profile) / $($gear.Gear) / $($gear.Model) / $($gear.Effort)"
    }
} else {
    Write-Host "CodexGear.psm1 not found."
}

Write-Section "Systems Backup"
if (Test-Path -LiteralPath $SystemsRepo) {
    $systemsBranch = Invoke-GitText -GitArgs @("branch", "--show-current") -WorkDir $SystemsRepo
    $systemsOrigin = Invoke-GitText -GitArgs @("remote", "get-url", "origin") -WorkDir $SystemsRepo
    $systemsHead = Invoke-GitText -GitArgs @("log", "-1", "--oneline") -WorkDir $SystemsRepo
    $systemsDirtyText = Invoke-GitText -GitArgs @("status", "--short") -WorkDir $SystemsRepo
    $systemsDirty = @($systemsDirtyText -split "`r?`n" | Where-Object { $_ })

    Write-Host "Repo: $SystemsRepo"
    Write-Host "Branch: $systemsBranch"
    Write-Host "Origin: $systemsOrigin"
    Write-Host "HEAD: $systemsHead"
    Write-Host "Dirty files: $($systemsDirty.Count)"
    foreach ($line in $systemsDirty) { Write-Host "  $line" }
} else {
    Write-Host "Systems repo not found: $SystemsRepo"
}

Write-Section "Useful Commands"
Write-Host "$scriptRoot\codex-systems-status.cmd"
Write-Host "$scriptRoot\codex-gear.cmd `"debug failing CI`""
Write-Host "$scriptRoot\codex-gear-test.cmd"
Write-Host "$scriptRoot\codex-gear-test.cmd -Smoke"
Write-Host "$scriptRoot\codex-handoff.cmd"
