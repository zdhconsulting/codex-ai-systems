param(
    [switch] $NoOpen,
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
    Write-Host "Usage: chatgpt-route.cmd `"TASK`""
    Write-Host "Use this for non-repo work such as writing, brainstorming, strategy, graphic design direction, summaries, learning, and second opinions."
    exit 1
}

$deliverableMode = if ($PacketOnly) {
    "Return only the CODEX_RETURN_PACKET block. Put the useful answer inside Deliverable."
} else {
    "Give the useful answer first, then end with the CODEX_RETURN_PACKET block."
}

$imageGenerationMode = $taskText -match "(?i)(\b(generate|create|make|produce)\b.*\b(images?|logos?|logo sheet|visual assets?|poster|ad creative|illustration|png|jpe?g|webp)\b|\b(images?|logos?|logo sheet|visual assets?|poster|ad creative|illustration|png|jpe?g|webp)\b.*\b(generate|create|make|produce)\b)"
$graphicGuidance = if ($imageGenerationMode) {
    "If this is graphic design or logo work and the user asks for actual images, do not stop at briefs. Use ChatGPT image generation to create the requested image asset(s) when available. Then include a CODEX_RETURN_PACKET that names what was generated and tells Codex to download, save, inspect, or wire the assets locally. If image generation is unavailable, say that clearly and provide production-ready prompts as the fallback deliverable."
} else {
    "If this is graphic design work, focus on direction, concepts, layouts, palettes, typography, prompts, and critique."
}

$prompt = @"
You are helping Zev through the ChatGPT route so Codex usage is preserved.

This task should not require local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, local asset editing, connected apps, private account actions, secrets, or production changes. If it does require those things, say that it should go back to Codex.

Your role is the detachable thinking lane. Do research, writing, synthesis, critique, brainstorming, translation, or planning that does not need Codex-local tools. Do not claim you inspected local files or accounts. Do not invent facts that require Zev's private account, inbox, repo, analytics, billing, or production data.

$graphicGuidance Do not generate or reinterpret a real person's face. If real-person face work is needed, tell Zev it should go back to Codex with the source image so the face can be preserved exactly.

Only invent client names, business facts, examples, or case details when the task explicitly asks for fictional, made-up, sample, mock, placeholder, or test content. Otherwise ask for the missing facts or mark them as needed.

Task:
$taskText

Deliverable:
- Be direct and useful.
- Give the best answer or artifact, not a menu unless a real decision is needed.
- If the user asked for actual images or logos, create the image asset(s) in ChatGPT when possible; do not return only strategy unless blocked.
- If there are assumptions, state them briefly.
- $deliverableMode
- Keep Codex next action concrete and local, such as "apply this copy to the landing page" or "no Codex action needed".
- Use "none" for empty fields.
- End with this exact return block so Zev can copy the result back into Codex:

CODEX_RETURN_PACKET
Summary:
Decisions:
Deliverable:
Codex next action:
Files/assets needed:
Owner buttons needed:
Confidence:
Go back to Codex?:
END_CODEX_RETURN_PACKET
"@

$copied = $false
try {
    Set-Clipboard -Value $prompt
    $copied = $true
} catch {
    Write-Warning "Could not copy prompt to clipboard: $($_.Exception.Message)"
}

if ($Print) {
    Write-Host $prompt
}

if ($OutFile) {
    $outDir = Split-Path -Parent $OutFile
    if ($outDir) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutFile -Value $prompt -Encoding UTF8
}

if ($PromptOnly) {
    if (-not $Print) {
        Write-Host $prompt
    }
    exit 0
}

if (-not $NoOpen) {
    Start-Process "https://chatgpt.com/"
}

if (-not $Quiet) {
    Write-Host "ChatGPT route prepared."
    if ($copied) {
        Write-Host "Prompt copied to clipboard."
    } else {
        Write-Host "Prompt was not copied. Re-run with -Print to view it."
    }
    if ($OutFile) {
        Write-Host "Prompt saved: $OutFile"
    }
    if (-not $NoOpen) {
        Write-Host "Opened ChatGPT. Paste the prompt if it is not inserted automatically."
    }
}
