param(
    [string] $Project = "General",
    [string] $InputFile = "",
    [switch] $Print
)

$ErrorActionPreference = "Stop"

if ($InputFile) {
    $text = Get-Content -LiteralPath $InputFile -Raw
} else {
    $clipboardLines = Get-Clipboard
    $text = ($clipboardLines -join [Environment]::NewLine)
}

if ([string]::IsNullOrWhiteSpace($text)) {
    Write-Host "No ChatGPT result found. Copy the ChatGPT answer, then run chatgpt-return.cmd again."
    exit 1
}

$safeProject = ($Project -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeProject)) {
    $safeProject = "General"
}

$handoffDir = Join-Path (Split-Path -Parent $PSScriptRoot) "handoffs\chatgpt"
New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$path = Join-Path $handoffDir "$stamp-$safeProject.txt"
Set-Content -LiteralPath $path -Value $text -Encoding UTF8

$hasPacket = $text -match "CODEX_RETURN_PACKET"

Write-Host "ChatGPT result imported."
Write-Host "Saved: $path"
if ($hasPacket) {
    Write-Host "Return packet: found"
} else {
    Write-Host "Return packet: not found. Codex can still use the saved text, but the handoff may be less structured."
}

if ($Print) {
    Write-Host ""
    Write-Host $text
}
