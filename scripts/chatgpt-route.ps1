param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Task,
    [switch] $NoOpen,
    [switch] $Print
)

$ErrorActionPreference = "Stop"
$taskText = (($Task | Where-Object { $_ }) -join " ").Trim()

if ([string]::IsNullOrWhiteSpace($taskText)) {
    Write-Host "Usage: chatgpt-route.cmd `"TASK`""
    Write-Host "Use this for non-repo work such as writing, brainstorming, strategy, graphic design direction, summaries, learning, and second opinions."
    exit 1
}

$prompt = @"
You are helping Zev through the ChatGPT route so Codex usage is preserved.

This task should not require local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, local asset editing, or private account actions. If it does require those things, say that it should go back to Codex.

If this is graphic design work, focus on direction, concepts, layouts, palettes, typography, prompts, and critique. Do not generate or reinterpret a real person's face. If real-person face work is needed, tell Zev it should go back to Codex with the source image so the face can be preserved exactly.

Task:
$taskText

Deliverable:
- Be direct and useful.
- Give the best answer or artifact, not a menu unless a real decision is needed.
- If there are assumptions, state them briefly.
- End with this exact return block so Zev can copy the result back into Codex:

CODEX_RETURN_PACKET
Summary:
Decisions:
Deliverable:
Codex next action:
Files/assets needed:
Owner buttons needed:
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
