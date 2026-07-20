---
name: chatgpt-desktop-bridge
description: Route bounded creative, design, writing, strategy, image-concept, or second-opinion work from a Codex task to Zev's exact existing ChatGPT Work conversation named Design Studio, then retrieve and validate its typed response without Chrome or a new chat. Use when Zev says to ask ChatGPT, use Design Studio, get design work from ChatGPT, hand work to the existing ChatGPT chat, or bring a ChatGPT result back into Codex.
---

# ChatGPT Desktop Bridge

Use the fixed existing ChatGPT Work conversation `Design Studio`. Keep Codex responsible for local
files, code, asset integration, tests, git, browser QA, deployment, and final verification.

## Endpoint Gate

Read `references/design-studio-endpoint.json` before sending. Require:

- `alias=chatgpt-design-studio`
- `mode=Work`
- `target_title=Design Studio`
- `transport=unified_desktop_uia`
- `existing_only=true`
- `create_if_missing=false`
- `live_send_enabled=true`
- `maximum_rounds=1`

Do not bypass a false live-send gate during ordinary work. `-SmokeTestOverride` is only for an
explicitly authorized bounded proof.

## Send And Retrieve

For a normal request, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\chatgpt-desktop-ui.ps1 `
  -Action send-receive `
  -TargetTitle 'Design Studio' `
  -PromptPath 'C:\absolute\path\to\bounded-prompt.txt' `
  -TimeoutSeconds 240
```

Use `-Prompt` only for short requests. Prefer `-PromptPath` for substantial design briefs.

The helper must:

1. Use the unified desktop app's named `Search` and `Command menu` controls.
2. Select exactly one existing result matching `Design Studio` and provider type `ChatGPT`.
3. Require `View chat history, current chat: Design Studio`, its bottom composer, and its named
   Send control before touching input.
4. Refuse to send while ChatGPT is busy or the composer contains an unsent draft.
5. Paste once only after the exact composer owns focus; verify the unique request token there.
6. Invoke the named Send button exactly once and never retry an ambiguous send.
7. Wait for one new assistant `Copy` control after generation becomes idle; user prompts expose a
   different `Copy message` control and must never satisfy response detection.
8. Copy and validate the matching `CHATGPT_RETURN_PACKET`, request ID, and completion marker.
9. Return to the originating Codex task through `CODEX_THREAD_ID` when available.

## Read-Only Checks

Use these checks while troubleshooting; they never send:

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
- Never stack work while Design Studio is thinking or another bridge request holds the mutex.
- Never use OCR, pixel positions, global keyboard-search shortcuts, private app databases, auth
  tokens, or Chrome for this route.
- Never retry after the named Send control is invoked if sent-state verification is ambiguous.
- Never run an unbounded AI-to-AI loop; one request receives one typed return packet.
- If the exact result, title, composer, focus, send control, or response receipt is ambiguous, return
  to Codex and report blocked without guessing.

Inspect all returned text and assets before applying them locally.
