param(
    [string] $CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

New-Item -ItemType Directory -Force `
    $CodexHome, `
    (Join-Path $CodexHome "scripts"), `
    (Join-Path $CodexHome "queues"), `
    (Join-Path $CodexHome "skills\owner-button-workflow\agents") | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot "instructions\AGENTS.md") `
    -Destination (Join-Path $CodexHome "AGENTS.md") -Force

Copy-Item -Path (Join-Path $repoRoot "scripts\*") `
    -Destination (Join-Path $CodexHome "scripts") -Force

Copy-Item -Path (Join-Path $repoRoot "profiles\*.config.toml") `
    -Destination $CodexHome -Force

Copy-Item -LiteralPath (Join-Path $repoRoot "skills\owner-button-workflow\SKILL.md") `
    -Destination (Join-Path $CodexHome "skills\owner-button-workflow\SKILL.md") -Force

Copy-Item -LiteralPath (Join-Path $repoRoot "skills\owner-button-workflow\agents\openai.yaml") `
    -Destination (Join-Path $CodexHome "skills\owner-button-workflow\agents\openai.yaml") -Force

$queuePath = Join-Path $CodexHome "queues\owner-buttons.json"
if (-not (Test-Path $queuePath)) {
    "[]" | Set-Content -Path $queuePath -Encoding UTF8
}

Write-Host "Installed Codex AI Systems to: $CodexHome"
Write-Host "Owner button queue: $queuePath"
Write-Host "Run this to verify:"
Write-Host "$CodexHome\scripts\git-guard.cmd"
