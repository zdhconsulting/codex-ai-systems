param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("5", "20", "60")]
    [string] $Minutes,
    [string] $AutomationPath = "$env:USERPROFILE\.codex\automations\zdh-worker-boss\automation.toml"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $AutomationPath)) {
    Write-Error "Worker Boss automation not found: $AutomationPath"
    exit 1
}

$text = Get-Content -LiteralPath $AutomationPath -Raw
$rrule = "FREQ=MINUTELY;INTERVAL=$Minutes"
if ($text -match '(?m)^rrule\s*=') {
    $text = [regex]::Replace($text, '(?m)^rrule\s*=.*$', "rrule = `"$rrule`"", 1)
} else {
    $text = $text.TrimEnd() + [Environment]::NewLine + "rrule = `"$rrule`"" + [Environment]::NewLine
}

$nowMs = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
if ($text -match '(?m)^updated_at\s*=') {
    $text = [regex]::Replace($text, '(?m)^updated_at\s*=.*$', "updated_at = $nowMs", 1)
}

Set-Content -LiteralPath $AutomationPath -Value $text -Encoding UTF8

Write-Host "ZDH Worker Boss interval set."
Write-Host "Automation: $AutomationPath"
Write-Host "Interval: every $Minutes minutes"
