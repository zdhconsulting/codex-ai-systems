param(
    [string] $CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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

Get-ChildItem -LiteralPath (Join-Path $repoRoot "skills") -Directory |
    ForEach-Object {
        $dest = Join-Path $CodexHome ("skills\" + $_.Name)
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item -Path (Join-Path $_.FullName "*") -Destination $dest -Recurse -Force
    }

$queuePath = Join-Path $CodexHome "queues\owner-buttons.json"
if (-not (Test-Path $queuePath)) {
    "[]" | Set-Content -Path $queuePath -Encoding UTF8
}

Write-Host "Installed Codex AI Systems to: $CodexHome"
Write-Host "Installed reusable skills from: $(Join-Path $repoRoot "skills")"
Write-Host "Owner button queue: $queuePath"
Write-Host "Run this to verify:"
Write-Host "$CodexHome\scripts\git-guard.cmd"
Write-Host "$CodexHome\scripts\codex-doctor.cmd"
Write-Host "$CodexHome\scripts\codex-gear-test.cmd"
Write-Host "$CodexHome\scripts\codex-systems-status.cmd"
Write-Host "$CodexHome\scripts\codex-project-freshness.cmd"
