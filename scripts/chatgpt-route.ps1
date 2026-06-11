param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Task,
    [switch] $NoOpen,
    [switch] $Print,
    [switch] $PacketOnly
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

$prompt = @"
You are helping Zev through the ChatGPT route so Codex usage is preserved.

This task should not require local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, local asset editing, connected apps, private account actions, secrets, or production changes. If it does require those things, say that it should go back to Codex.

Your role is the detachable thinking lane. Do research, writing, synthesis, critique, brainstorming, translation, or planning that does not need Codex-local tools. Do not claim you inspected local files or accounts. Do not invent facts that require Zev's private account, inbox, repo, analytics, billing, or production data.

If this is graphic design work, focus on direction, concepts, layouts, palettes, typography, prompts, and critique. Do not generate or reinterpret a real person's face. If real-person face work is needed, tell Zev it should go back to Codex with the source image so the face can be preserved exactly.

Task:
$taskText

Deliverable:
- Be direct and useful.
- Give the best answer or artifact, not a menu unless a real decision is needed.
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

if (-not $NoOpen) {
    Start-Process "https://chatgpt.com/"
}

Write-Host "ChatGPT route prepared."
if ($copied) {
    Write-Host "Prompt copied to clipboard."
} else {
    Write-Host "Prompt was not copied. Re-run with -Print to view it."
}
if (-not $NoOpen) {
    Write-Host "Opened ChatGPT. Paste the prompt if it is not inserted automatically."
}
