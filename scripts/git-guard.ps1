param(
    [string] $Cwd = (Get-Location).Path
)

Set-Location -LiteralPath $Cwd

$inside = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
    Write-Error "Not inside a git repository: $Cwd"
    exit 1
}

$root = git rev-parse --show-toplevel
$branch = git branch --show-current
$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) { $remote = "(no origin remote)" }
$head = git log -1 --pretty=format:"%h %s" 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
    $head = "(no commits yet)"
}
$statusLines = @(git status --short)

Write-Host "Git Guard"
Write-Host "Repo: $root"
Write-Host "Branch: $branch"
Write-Host "Origin: $remote"
Write-Host "HEAD: $head"

if ($statusLines.Count -eq 0) {
    Write-Host "Dirty files: none"
} else {
    Write-Host "Dirty files: $($statusLines.Count)"
    $statusLines | Select-Object -First 80 | ForEach-Object { Write-Host "  $_" }
    if ($statusLines.Count -gt 80) {
        Write-Host "  ... $($statusLines.Count - 80) more omitted"
    }
}

Write-Host ""
Write-Host "Before commit/push, confirm this repo, branch, remote, and file list match the user's intended project."
