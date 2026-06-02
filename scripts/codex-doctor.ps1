param(
    [string] $Cwd = (Get-Location).Path,
    [string] $Task = "debug failing CI",
    [switch] $Smoke
)

$ErrorActionPreference = "Continue"
$script:Failures = New-Object System.Collections.Generic.List[string]
$scriptRoot = $PSScriptRoot
$codexHome = Split-Path -Parent $scriptRoot

function Invoke-DoctorStep {
    param(
        [string] $Name,
        [scriptblock] $Block
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $Block
    if ($LASTEXITCODE -ne 0) {
        $script:Failures.Add($Name)
        Write-Host "Doctor step failed: $Name"
    }
}

Write-Host "Codex doctor"
Write-Host "Codex home: $codexHome"
Write-Host "Workspace: $Cwd"
Write-Host "Smoke: $([bool]$Smoke)"

Invoke-DoctorStep -Name "Systems status" -Block {
    & (Join-Path $scriptRoot "codex-systems-status.ps1") -CodexHome $codexHome -Task $Task
}

Invoke-DoctorStep -Name "Gear test" -Block {
    if ($Smoke) {
        & (Join-Path $scriptRoot "codex-gear-test.ps1") -CodexHome $codexHome -Smoke
    } else {
        & (Join-Path $scriptRoot "codex-gear-test.ps1") -CodexHome $codexHome
    }
}

$inside = & git -C $Cwd rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -eq 0 -and $inside.Trim() -eq "true") {
    Invoke-DoctorStep -Name "Git guard" -Block {
        & (Join-Path $scriptRoot "git-guard.ps1") -Cwd $Cwd
    }
} else {
    Write-Host ""
    Write-Host "== Git guard =="
    Write-Host "Skipped: not inside a git repo."
}

Write-Host ""
Write-Host "Codex doctor summary"
if ($script:Failures.Count -eq 0) {
    Write-Host "Failures: 0"
    exit 0
}

Write-Host "Failures: $($script:Failures.Count)"
foreach ($failure in $script:Failures) {
    Write-Host "  $failure"
}
exit 1
