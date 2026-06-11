param(
    [string] $ProjectPath = (Get-Location).Path,
    [switch] $DryRun,
    [switch] $Print
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    Write-Error "Project path not found: $ProjectPath"
    exit 1
}

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
$agentsPath = Join-Path $projectRoot "AGENTS.md"
$startMarker = "<!-- ZEV_CODEX_WORKFLOW_START -->"
$endMarker = "<!-- ZEV_CODEX_WORKFLOW_END -->"

$block = @'
<!-- ZEV_CODEX_WORKFLOW_START -->
# Personal Codex Workflow

Use `$owner-button-workflow`, `$chatgpt-routing`, and `$codex-chatgpt-bridge` for Zev's projects.

Codex should drive implementation work fast: code, tests, debugging, verification, commits, pushes, deployment prep, browser automation, ChatGPT orchestration, and clear explanations.

Zev should only be pulled in for real-world owner-only tasks: account logins, env vars or secrets from private accounts, billing/security prompts, account verification, deploy buttons that require Zev's session, CAPTCHA, payment/account verification, and explicit approvals.

Use `Owner button needed` only when truly blocked by an external account or user-only action. Include the exact site/tool, exact action, why Codex cannot do it, and what Codex will do next.

Use `Commander approval needed` only when Zev needs to approve a next step that affects strategy, cost, risk, production state, permissions, or repo history.

When Zev reports an owner-only task is complete, say exactly:

`GATE BROKEN. Owner button pressed. We're through.`

Then immediately continue working.

## Next Protocol

When Zev says `Next`, continue the current mission with the best next action. Do not ask what `Next` means unless a real approval decision is required.

## Reasoning Gear

Start substantial tasks with `Gear: low|medium|high|xhigh - brief reason`. Use low for simple mechanical work, medium for normal implementation, high for debugging/verification-heavy work, and xhigh for architecture, auth, billing, security, database, permissions, or production-risk work.

## AI Credits Usage Optimizer

Use `C:\Users\zev\.codex\scripts\codex-auto.cmd "TASK"` for new CLI/automation work. It runs an AI credits optimizer before launching Codex and diverts obvious non-repo writing, brainstorming, strategy, summaries, explanations, and design-direction tasks to ChatGPT.

Preview or dispatch with `C:\Users\zev\.codex\scripts\ai-credits-optimizer.cmd -DryRun "TASK"`. Force Codex with `-ForceCodex`, `[codex]`, or `--codex`; force ChatGPT with `-ForceChatGPT`, `[chatgpt]`, or `--chatgpt`.

Use `$codex-chatgpt-bridge` for routing edge cases, bounded ChatGPT handoffs, and return-packet imports. After ChatGPT returns an answer, import it with `C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print -RequirePacket`.

## ChatGPT Auto-Orchestration

Route non-repo writing, brainstorming, strategy, summaries, learning, second opinions, and graphic design direction to ChatGPT to preserve Codex usage.

Use `C:\Users\zev\.codex\scripts\codex-gateway.cmd -DryRun "TASK"` before substantial non-local work. The gateway reuses exact cached ChatGPT packets/assets when safe, bypasses cache for current/latest/today/news/price/weather/schedule style prompts, and shows estimated avoided Codex work plus current rate-limit pressure. Use `-Refresh` to force a fresh ChatGPT run, `-NoCache` to test raw routing, and `-SplitHybrid` only when the ChatGPT-safe part is obvious and Codex will apply or verify locally afterward.

Use `C:\Users\zev\.codex\scripts\codex-gateway-tally.cmd` to review route counts, ChatGPT moves, cache hits, completions, savings estimates, and the reason/signals for each decision.

After notable routes, log quality with `C:\Users\zev\.codex\scripts\codex-gateway-feedback.cmd -SessionPath "SESSION_JSON" -Rating 1-5 -Outcome good|mixed|bad -Notes "..."`.

When Chrome/ChatGPT web is available, automate the whole route: open or claim ChatGPT, submit the prompt, wait for completion, copy/import text results, or download generated image assets. Manual paste/copy is fallback only when browser automation is unavailable or ChatGPT requires login, CAPTCHA, payment, account verification, safety confirmation, or another owner-only action.

For ChatGPT image generation, Codex is the orchestrator: prepare an IP-safe prompt, submit it through ChatGPT web, wait for the image, download the generated asset, save it to the project assets folder when one is obvious or `C:\Users\zev\OneDrive\Documents\ZDH Generated Assets`, visually inspect it, and return the local file link plus image preview.

Avoid exact copyrighted characters, logos, brand trade dress, and real-person face reinterpretation unless Zev supplies allowed source material and exact preservation is possible.

Keep work in Codex for code, repo inspection, local files, tests, builds, commits, pushes, PRs, deployments, CI, logs, screenshots, browser/app verification, durable `.codex` system changes, active goals, owner-button queues, actual local asset editing, web/app UI implementation, brand-system work, and production-risk work.

## Safety

Before any commit, push, deploy, branch creation, PR creation, or destructive git operation, run:

`C:\Users\zev\.codex\scripts\git-guard.cmd`

After changing user-level Codex workflow files under `C:\Users\zev\.codex`, run:

`C:\Users\zev\.codex\scripts\save-codex-systems.cmd`
<!-- ZEV_CODEX_WORKFLOW_END -->
'@

if (Test-Path -LiteralPath $agentsPath) {
    $current = Get-Content -LiteralPath $agentsPath -Raw
    if ($current.Contains($startMarker) -and $current.Contains($endMarker)) {
        $pattern = "(?s)" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
        $updated = [regex]::Replace($current, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }, 1)
    } else {
        $updated = $block + [Environment]::NewLine + [Environment]::NewLine + $current
    }
} else {
    $updated = $block
}

if ($DryRun) {
    Write-Host "Project rules dry run. No files changed."
} else {
    Set-Content -LiteralPath $agentsPath -Value $updated -Encoding UTF8
    Write-Host "Project rules installed."
}
Write-Host "Project: $projectRoot"
Write-Host "AGENTS: $agentsPath"
if ($Print -or $DryRun) {
    Write-Host ""
    Write-Host $updated
}
