param(
    [string] $ProjectPath = (Get-Location).Path,
    [string] $OutFile = "",
    [switch] $NoClipboard
)

$codexHome = Join-Path $env:USERPROFILE ".codex"
$handoffDir = Join-Path $codexHome "handoffs"
$systemsRepo = "C:\Repos\codex-ai-systems"

New-Item -ItemType Directory -Force $handoffDir | Out-Null

function Get-GitSnapshot {
    param([string] $Path)

    $inside = git -C $Path rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
        return [pscustomobject]@{
            IsRepo = $false
            Root = $Path
            Branch = "(not a git repo)"
            Origin = "(not a git repo)"
            Head = "(not a git repo)"
            Status = @()
        }
    }

    $root = (git -C $Path rev-parse --show-toplevel).Trim()
    $branch = (git -C $root branch --show-current).Trim()
    $origin = git -C $root remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
        $origin = "(no origin remote)"
    }
    $head = git -C $root log -1 --pretty=format:"%h %s" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        $head = "(no commits yet)"
    }
    $status = @(git -C $root status --short)

    return [pscustomobject]@{
        IsRepo = $true
        Root = $root
        Branch = $branch
        Origin = $origin
        Head = $head
        Status = $status
    }
}

function Get-OwnerButtonSnapshot {
    $queuePath = Join-Path $codexHome "queues\owner-buttons.json"
    if (-not (Test-Path $queuePath)) {
        return [pscustomobject]@{
            Path = $queuePath
            Open = @()
        }
    }

    $raw = Get-Content -Path $queuePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $items = @()
    } else {
        $items = @($raw | ConvertFrom-Json)
    }

    return [pscustomobject]@{
        Path = $queuePath
        Open = @($items | Where-Object { $_.Status -eq "open" })
    }
}

$project = Get-GitSnapshot -Path $ProjectPath
$systems = Get-GitSnapshot -Path $systemsRepo
$queue = Get-OwnerButtonSnapshot

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutFile = Join-Path $handoffDir "codex-handoff-$stamp.md"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Codex Handoff")
$lines.Add("")
$lines.Add("Generated: $(Get-Date -Format s)")
$lines.Add("Machine user: $env:USERNAME")
$lines.Add("")
$lines.Add("## What To Install On A New Computer")
$lines.Add("")
$lines.Add('```powershell')
$lines.Add("mkdir C:\Repos")
$lines.Add("git clone https://github.com/zdhconsulting/codex-ai-systems.git C:\Repos\codex-ai-systems")
$lines.Add("cd C:\Repos\codex-ai-systems")
$lines.Add("powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1")
$lines.Add('```')
$lines.Add("")
$lines.Add("## Systems Repo")
$lines.Add("")
$lines.Add("- Repo: $($systems.Root)")
$lines.Add("- Branch: $($systems.Branch)")
$lines.Add("- Origin: $($systems.Origin)")
$lines.Add("- HEAD: $($systems.Head)")
if ($systems.Status.Count -eq 0) {
    $lines.Add("- Dirty files: none")
} else {
    $lines.Add("- Dirty files: $($systems.Status.Count)")
    foreach ($line in ($systems.Status | Select-Object -First 40)) {
        $lines.Add("  - $line")
    }
}
$lines.Add("")
$lines.Add("## Current Project")
$lines.Add("")
$lines.Add("- Path: $($project.Root)")
$lines.Add("- Is git repo: $($project.IsRepo)")
$lines.Add("- Branch: $($project.Branch)")
$lines.Add("- Origin: $($project.Origin)")
$lines.Add("- HEAD: $($project.Head)")
if ($project.Status.Count -eq 0) {
    $lines.Add("- Dirty files: none")
} else {
    $lines.Add("- Dirty files: $($project.Status.Count)")
    foreach ($line in ($project.Status | Select-Object -First 80)) {
        $lines.Add("  - $line")
    }
}
$lines.Add("")
$lines.Add("## Owner Buttons")
$lines.Add("")
$lines.Add("- Queue: $($queue.Path)")
$lines.Add("- Open owner buttons: $($queue.Open.Count)")
foreach ($item in $queue.Open) {
    $lines.Add("")
    $lines.Add("### $($item.Id)")
    $lines.Add("")
    $lines.Add("- Project: $($item.Project)")
    $lines.Add("- Site/tool: $($item.Site)")
    $lines.Add("- Needed: $($item.Needed)")
    if ($item.Why) { $lines.Add("- Why: $($item.Why)") }
    if ($item.Next) { $lines.Add("- Codex next: $($item.Next)") }
}
$lines.Add("")
$lines.Add("## Paste This Into The Other Codex")
$lines.Add("")
$lines.Add('```text')
$lines.Add("Use ~/.codex/AGENTS.md and `$owner-button-workflow.")
$lines.Add("Verify owner-button workflow, reasoning gears, and git guard are installed.")
$lines.Add("Project repo: $($project.Origin)")
$lines.Add("Expected branch: $($project.Branch)")
$lines.Add("Expected latest commit: $($project.Head)")
$lines.Add("Start by running git status, git pull --ff-only where safe, and owner-button list.")
$lines.Add("Continue from GitHub. Only ask Zev for Owner button needed or Commander approval needed when truly blocked.")
$lines.Add('```')

$content = $lines -join [Environment]::NewLine
$content | Set-Content -Path $OutFile -Encoding UTF8

if (-not $NoClipboard) {
    try {
        Set-Clipboard -Value $content
        Write-Host "Copied handoff text to clipboard."
    } catch {
        Write-Host "Clipboard copy failed; handoff file was still written."
    }
}

Write-Host "Codex handoff written:"
Write-Host $OutFile
