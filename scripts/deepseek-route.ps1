param(
    [string] $Project = "General",
    [int] $ProviderReadyTimeoutSeconds = 30,
    [switch] $AllowProviderFallback,
    [switch] $FirmProvider,
    [switch] $NoOpen,
    [switch] $NoCopy,
    [switch] $Print,
    [switch] $PacketOnly,
    [switch] $PromptOnly,
    [switch] $Quiet,
    [string] $OutFile = "",
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Task
)

$ErrorActionPreference = "Stop"
$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: deepseek-route.cmd [-Project NAME] [-NoOpen] `"TASK`""
    Write-Host "Use this for low-cost first-pass drafts, bulk long-form content, SEO article packets, comparison drafts, and rough structured thinking that does not need local files."
    exit 1
}

$codexHome = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $codexHome "logs\deepseek-bridge"
$eventsPath = Join-Path $logRoot "events.jsonl"

function ConvertTo-SafeName {
    param([string] $Value)
    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "General" }
    return $safe
}

function Write-DeepSeekEvent {
    param([object] $Event)
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $line = $Event | ConvertTo-Json -Compress -Depth 8
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $line | Add-Content -LiteralPath $eventsPath -Encoding UTF8
            return
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
    Write-Warning "Could not append DeepSeek bridge event after retries: $eventsPath"
}

function ConvertTo-PowerShellSingleQuotedArgument {
    param([string] $Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Open-UrlInChrome {
    param([string] $Url)
    $chromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($candidate in $chromeCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            Start-Process -FilePath $candidate -ArgumentList $Url | Out-Null
            return $true
        }
    }
    Start-Process $Url
    return $false
}

$deliverableMode = if ($PacketOnly) {
    "Return only the CODEX_RETURN_PACKET block. Put the useful answer inside Deliverable."
} else {
    "Give the useful answer first, then end with the CODEX_RETURN_PACKET block."
}

$providerReadyTimeoutSeconds = [Math]::Max(5, $ProviderReadyTimeoutSeconds)
$providerFirm = [bool]($FirmProvider -or -not $AllowProviderFallback)
$codexAutoCmd = Join-Path $PSScriptRoot "codex-auto.cmd"
$codexFallbackCommand = if (-not $providerFirm) {
    "& $(ConvertTo-PowerShellSingleQuotedArgument $codexAutoCmd) -ForceCodex -NoOptimizeCredits $(ConvertTo-PowerShellSingleQuotedArgument $taskText)"
} else {
    ""
}
$providerFallbackPolicy = [ordered]@{
    Provider = "deepseek"
    Firm = $providerFirm
    CodexFallbackAllowed = (-not $providerFirm)
    ProviderReadyTimeoutSeconds = $providerReadyTimeoutSeconds
    CodexFallbackCommand = $codexFallbackCommand
    Reason = if ($providerFirm) {
        "Provider route is firm because DeepSeek was directly requested or provider fallback was disabled."
    } else {
        "Provider route is soft; if DeepSeek is not ready quickly, continue in Codex."
    }
}

$prompt = @"
You are helping Zev through the DeepSeek route so Codex usage is preserved and the cheapest capable model handles the right work.

Use DeepSeek as the low-cost first-pass lane. You are a good fit for bulk drafts, SEO article drafts, long-form outlines, alternate drafts, comparison drafts, rough structured analysis, and volume work where Codex will do local QA, repo edits, publishing, tests, git, and verification.

Do not claim access to local files, repos, browsers, accounts, analytics, secrets, billing, deployment state, or private data. If the task requires those, say it should go back to Codex. If the task needs premium image generation, high-stakes brand polish, or client-ready final creative, say ChatGPT is the better next provider unless the user explicitly requested DeepSeek.

Only invent client names, business facts, examples, or case details when the task explicitly asks for fictional, made-up, sample, mock, placeholder, or test content. Otherwise mark missing facts as needed.

Task:
$taskText

Deliverable:
- Be direct and useful.
- Prefer one strong draft or packet over a menu of options unless the task asks for options.
- Include assumptions briefly.
- $deliverableMode
- Keep Codex next action concrete and local, such as "QA this draft against the publishing gate" or "no Codex action needed".
- Use "none" for empty fields.
- End with this exact return block so Zev can copy the result back into Codex:

CODEX_RETURN_PACKET
Summary:
Provider used: DeepSeek
Decisions:
Deliverable:
Codex next action:
Files/assets needed:
Owner buttons needed:
Confidence:
Go back to Codex?:
END_CODEX_RETURN_PACKET
"@

$safeProject = ConvertTo-SafeName $Project
$sessionId = Get-Date -Format "yyyyMMdd-HHmmss"
$sessionDir = Join-Path $logRoot "$sessionId-$safeProject"
$promptPath = if ($OutFile) { $OutFile } else { Join-Path $sessionDir "prompt.txt" }
$responsePath = Join-Path $sessionDir "response.txt"
$sessionPath = Join-Path $sessionDir "session.json"

New-Item -ItemType Directory -Path (Split-Path -Parent $promptPath) -Force | Out-Null
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
Set-Content -LiteralPath $promptPath -Value $prompt -Encoding UTF8

$copied = $false
if (-not $NoCopy) {
    try {
        Set-Clipboard -Value $prompt
        $copied = $true
    } catch {
        Write-Warning "Could not copy prompt to clipboard: $($_.Exception.Message)"
    }
}

if ($Print -or $PromptOnly) {
    Write-Host $prompt
}

$opened = $false
if (-not $NoOpen -and -not $PromptOnly) {
    Open-UrlInChrome "https://chat.deepseek.com/" | Out-Null
    $opened = $true
}

$session = [ordered]@{
    SessionId = $sessionId
    Status = "prepared"
    CreatedAt = (Get-Date).ToString("o")
    Project = $Project
    Provider = "deepseek"
    Task = $taskText
    PromptPath = $promptPath
    ResponsePath = $responsePath
    SessionPath = $sessionPath
    OpenedDeepSeek = $opened
    CopiedPrompt = $copied
    ProviderFallbackPolicy = $providerFallbackPolicy
    DeepSeekUrl = "https://chat.deepseek.com/"
    NextManualAction = "Paste the prompt into DeepSeek if needed, wait for the CODEX_RETURN_PACKET, then import it with chatgpt-return.cmd -Print -RequirePacket or a project-specific importer."
}
$session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

Write-DeepSeekEvent ([ordered]@{
    Type = "prepared"
    At = (Get-Date).ToString("o")
    Project = $Project
    Provider = "deepseek"
    Route = "deepseek"
    Task = $taskText
    PromptPath = $promptPath
    ResponsePath = $responsePath
    SessionPath = $sessionPath
    OpenedDeepSeek = $opened
    CopiedPrompt = $copied
    ProviderFallbackPolicy = $providerFallbackPolicy
})

if (-not $Quiet -and -not $PromptOnly) {
    Write-Host "DeepSeek route prepared."
    Write-Host "Provider: deepseek"
    $mode = if ($providerFallbackPolicy.Firm) { "firm" } else { "soft" }
    $fallbackText = if ($providerFallbackPolicy.CodexFallbackAllowed) { "Codex fallback allowed after $($providerFallbackPolicy.ProviderReadyTimeoutSeconds)s readiness failure" } else { "no automatic Codex fallback" }
    Write-Host "Provider route: $mode ($fallbackText)"
    if ($providerFallbackPolicy.CodexFallbackCommand) { Write-Host "Fallback command: $($providerFallbackPolicy.CodexFallbackCommand)" }
    Write-Host "Session: $sessionPath"
    Write-Host "Prompt: $promptPath"
    Write-Host "Response: $responsePath"
    if ($copied) { Write-Host "Prompt copied to clipboard." }
    if ($opened) { Write-Host "Opened DeepSeek." }
}

exit 0
