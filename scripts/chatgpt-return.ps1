param(
    [string] $Project = "General",
    [string] $InputFile = "",
    [switch] $Print,
    [switch] $RequirePacket,
    [switch] $Json
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

$hasPacketMarker = $text -match "CODEX_RETURN_PACKET"
$match = [regex]::Match($text, "(?s)CODEX_RETURN_PACKET\s*(.*?)\s*END_CODEX_RETURN_PACKET")
$hasPacket = $match.Success
$packetError = ""
if ($hasPacketMarker -and -not $hasPacket) {
    $packetError = "CODEX_RETURN_PACKET marker found, but END_CODEX_RETURN_PACKET is missing."
}
$packet = [ordered]@{}
if ($hasPacket) {
    $packetText = $match.Groups[1].Value.Trim()
    $fieldNames = @("Summary", "Decisions", "Deliverable", "Codex next action", "Files/assets needed", "Owner buttons needed", "Confidence", "Go back to Codex?")
    for ($i = 0; $i -lt $fieldNames.Count; $i++) {
        $name = $fieldNames[$i]
        $nextName = if ($i -lt ($fieldNames.Count - 1)) { $fieldNames[$i + 1] } else { $null }
        $pattern = if ($nextName) {
            "(?s)(?:^|\r?\n)$([regex]::Escape($name)):\s*(.*?)(?=\r?\n$([regex]::Escape($nextName)):\s*)"
        } else {
            "(?s)(?:^|\r?\n)$([regex]::Escape($name)):\s*(.*)$"
        }
        $fieldMatch = [regex]::Match($packetText, $pattern)
        if ($fieldMatch.Success) {
            $packet[$name] = $fieldMatch.Groups[1].Value.Trim()
        } else {
            $packet[$name] = ""
        }
    }
}

if ($RequirePacket -and -not $hasPacket) {
    if ($packetError) {
        Write-Host "ChatGPT result imported but the CODEX_RETURN_PACKET block is malformed."
        Write-Host $packetError
    } else {
        Write-Host "ChatGPT result imported but no complete CODEX_RETURN_PACKET block was found."
    }
    Write-Host "Saved: $path"
    exit 2
}

if ($Json) {
    [pscustomobject]@{
        Saved = $path
        HasPacket = $hasPacket
        PacketError = $packetError
        Packet = $packet
        Text = if ($Print) { $text } else { "" }
    } | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host "ChatGPT result imported."
Write-Host "Saved: $path"
if ($hasPacket) {
    Write-Host "Return packet: found"
    foreach ($key in $packet.Keys) {
        if ($packet[$key]) {
            $value = $packet[$key]
            if ($value.Length -gt 240) {
                $value = $value.Substring(0, 237) + "..."
            }
            Write-Host "${key}: $value"
        }
    }
} else {
    Write-Host "Return packet: not found. Codex can still use the saved text, but the handoff may be less structured."
}

if ($Print) {
    Write-Host ""
    Write-Host $text
}
