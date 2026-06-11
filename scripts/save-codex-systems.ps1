param(
    [string] $RepoPath = "C:\Repos\codex-ai-systems",
    [string] $RemoteUrl = "https://github.com/zdhconsulting/codex-ai-systems.git",
    [switch] $NoPush
)

$codexHome = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $RepoPath)) {
    Write-Error "Repo path not found: $RepoPath"
    exit 1
}

New-Item -ItemType Directory -Force `
    (Join-Path $RepoPath "instructions"), `
    (Join-Path $RepoPath "profiles"), `
    (Join-Path $RepoPath "scripts"), `
    (Join-Path $RepoPath "queues"), `
    (Join-Path $RepoPath "skills"), `
    (Join-Path $RepoPath "skills\owner-button-workflow\agents") | Out-Null

Copy-Item -LiteralPath (Join-Path $codexHome "AGENTS.md") `
    -Destination (Join-Path $RepoPath "instructions\AGENTS.md") -Force

Copy-Item -Path (Join-Path $codexHome "scripts\*.ps1") `
    -Destination (Join-Path $RepoPath "scripts") -Force

Copy-Item -Path (Join-Path $codexHome "scripts\*.cmd") `
    -Destination (Join-Path $RepoPath "scripts") -Force

Copy-Item -Path (Join-Path $codexHome "scripts\*.psm1") `
    -Destination (Join-Path $RepoPath "scripts") -Force

Copy-Item -Path (Join-Path $codexHome "scripts\*.mjs") `
    -Destination (Join-Path $RepoPath "scripts") -Force

Copy-Item -Path (Join-Path $codexHome "*.config.toml") `
    -Destination (Join-Path $RepoPath "profiles") -Force

Copy-Item -LiteralPath (Join-Path $codexHome "skills\owner-button-workflow\SKILL.md") `
    -Destination (Join-Path $RepoPath "skills\owner-button-workflow\SKILL.md") -Force

Copy-Item -LiteralPath (Join-Path $codexHome "skills\owner-button-workflow\agents\openai.yaml") `
    -Destination (Join-Path $RepoPath "skills\owner-button-workflow\agents\openai.yaml") -Force

Get-ChildItem -LiteralPath (Join-Path $codexHome "skills") -Directory |
    Where-Object { $_.Name -ne ".system" } |
    ForEach-Object {
        $dest = Join-Path $RepoPath ("skills\" + $_.Name)
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item -Path (Join-Path $_.FullName "*") -Destination $dest -Recurse -Force
    }

$queueExample = Join-Path $RepoPath "queues\owner-buttons.example.json"
if (-not (Test-Path $queueExample)) {
    "[]" | Set-Content -Path $queueExample -Encoding UTF8
}

Set-Location -LiteralPath $RepoPath

$inside = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
    Write-Error "Not a git repository: $RepoPath"
    exit 1
}

$branch = git branch --show-current
if ($branch -ne "main") {
    Write-Error "Commander approval needed: codex-ai-systems auto-save expected branch main, found $branch."
    exit 1
}

$origin = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $origin -ne $RemoteUrl) {
    Write-Error "Commander approval needed: origin is $origin, expected $RemoteUrl."
    exit 1
}

git add .
$changes = git status --short
if ([string]::IsNullOrWhiteSpace(($changes | Out-String))) {
    Write-Host "Codex AI Systems auto-save: no changes to commit."
} else {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git commit -m "Auto-save Codex AI systems $stamp"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($NoPush) {
    Write-Host "Codex AI Systems auto-save: skipped push because -NoPush was set."
    exit 0
}

$origin = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Owner button needed: create GitHub repo zdhconsulting/codex-ai-systems, then run:"
    Write-Host "git -C $RepoPath remote add origin $RemoteUrl"
    Write-Host "$codexHome\scripts\save-codex-systems.cmd"
    exit 2
}

git push -u origin main
exit $LASTEXITCODE
