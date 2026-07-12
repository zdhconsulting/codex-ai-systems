---
name: chatgpt-desktop-bridge
description: Route bounded creative, design, writing, strategy, or second-opinion work from a Codex task to Zev's exact existing ChatGPT Work conversation named Design Studio, then retrieve and validate its typed response without Chrome or a new chat. Use when Zev says to ask ChatGPT, use Design Studio, hand work to the existing ChatGPT chat, or bring a ChatGPT result back into Codex.
---

# ChatGPT Desktop Bridge

Use the fixed existing ChatGPT Work conversation `Design Studio`. Keep Codex responsible for local
files, code, tests, git, browser QA, deployment, and final integration.

## Endpoint Contract

Read `references/design-studio-endpoint.json` before sending. Require:

- `alias=chatgpt-design-studio`
- `mode=Work`
- `target_title=Design Studio`
- `existing_only=true`
- `create_if_missing=false`
- `live_send_enabled=true`

Do not bypass a false live-send gate during ordinary work. `-SmokeTestOverride` is only for the one
explicitly authorized bounded proof that enables the endpoint.

## Send And Retrieve

Run the deterministic helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\chatgpt-desktop-ui.ps1 `
  -Action send-receive `
  -TargetTitle 'Design Studio' `
  -PromptPath 'C:\absolute\path\to\bounded-prompt.txt' `
  -TimeoutSeconds 240
```

The helper must:

1. Switch to ChatGPT Work through OCR-verified labels.
2. Open Chat and select the exact existing `Design Studio` History entry.
3. Require the paired `Add to task` header control so main-task text cannot impersonate the panel.
4. Refuse to send while ChatGPT is busy or the composer is not provably empty.
5. Paste once, verify the unique request token, and press Enter once.
6. Wait only for the matching completion marker.
7. Use the response's native copy control and validate the matching `CHATGPT_RETURN_PACKET`.
8. Return to the originating Codex task through `CODEX_THREAD_ID`.

Use `-Prompt` only for short bounded requests. Prefer `-PromptPath` for substantial work.

## Read-Only Checks

Use these while troubleshooting; they never send:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\chatgpt-desktop-ui.ps1 `
  -Action open-chat -TargetTitle 'Design Studio'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\chatgpt-desktop-ui.ps1 `
  -Action copy-latest -TargetTitle 'Design Studio' -ExpectedMarker 'VISIBLE UNIQUE MARKER'
```

## Fail Closed

- Never create, fork, rename, or silently switch ChatGPT conversations.
- Never overwrite or clear an existing user draft.
- Never stack work while Design Studio is thinking.
- Never retry after Enter if visual sent-state verification fails.
- Never use global command-menu shortcuts, private app databases, auth tokens, or Chrome for this route.
- Never run an unbounded AI-to-AI loop; one request receives one typed return packet.
- If the renderer is blank, the title/control pair is ambiguous, or the composer is not empty, return
  to Codex and report blocked without sending.

Inspect all returned text and assets before applying them locally.
