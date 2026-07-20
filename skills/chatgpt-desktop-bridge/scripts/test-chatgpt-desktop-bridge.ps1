[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $PSScriptRoot 'chatgpt-desktop-ui.ps1'
$endpointPath = Join-Path $skillRoot 'references\design-studio-endpoint.json'
$skillPath = Join-Path $skillRoot 'SKILL.md'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $uiScript,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    throw ($parseErrors | ForEach-Object Message | Out-String)
}

$endpoint = Get-Content -Raw -LiteralPath $endpointPath | ConvertFrom-Json
$expected = [ordered]@{
    alias = 'chatgpt-design-studio'
    mode = 'Work'
    target_title = 'Design Studio'
    transport = 'unified_desktop_uia'
    app_generation = 'unified-chatgpt-desktop-2026-07'
    existing_only = $true
    create_if_missing = $false
    maximum_rounds = 1
}
foreach ($entry in $expected.GetEnumerator()) {
    if ($endpoint.($entry.Key) -ne $entry.Value) {
        throw "Endpoint field '$($entry.Key)' has an invalid value."
    }
}

$uiText = Get-Content -Raw -LiteralPath $uiScript
foreach ($required in @(
    'UIAutomationClient',
    'Command menu',
    'View chat history, current chat:',
    "Current.Name -eq 'Copy'",
    'Local\ZevChatGptDesignStudioBridge',
    'unified_desktop_uia'
)) {
    if ($uiText -notmatch [regex]::Escape($required)) {
        throw "Desktop helper is missing required UIA contract text: $required"
    }
}
foreach ($retired in @(
    'Windows.Media.Ocr',
    'desktop_ocr_ui',
    'Get-WorkView',
    'Get-OcrWordMatches',
    'SetCursorPos',
    'mouse_event'
)) {
    if ($uiText -match [regex]::Escape($retired)) {
        throw "Desktop helper still contains retired fragile transport: $retired"
    }
}

$skillText = Get-Content -Raw -LiteralPath $skillPath
foreach ($required in @(
    'Design Studio',
    'existing_only=true',
    'create_if_missing=false',
    'transport=unified_desktop_uia',
    'CHATGPT_RETURN_PACKET'
)) {
    if ($skillText -notmatch [regex]::Escape($required)) {
        throw "SKILL.md is missing required contract text: $required"
    }
}
foreach ($retired in @('OCR-verified', 'Work drawer', 'open-command-menu')) {
    if ($skillText -match [regex]::Escape($retired)) {
        throw "SKILL.md still references retired transport: $retired"
    }
}

[pscustomobject]@{
    ok = $true
    ui_script_parse = 'passed'
    endpoint_contract = 'passed'
    uia_guardrails = 'passed'
    skill_contract = 'passed'
    live_send_enabled = [bool]$endpoint.live_send_enabled
    send_roundtrip_proven = [bool]$endpoint.send_roundtrip_proven
} | ConvertTo-Json -Depth 4
