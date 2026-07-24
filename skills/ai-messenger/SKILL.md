---
name: ai-messenger
description: Route bounded, typed work between a named Codex project task and specific Claude, ChatGPT, DeepSeek, or Codex endpoints through the PC-local AI Messenger. Use when Zev asks one AI chat to speak to another, asks a project to use the bridge, registers a new project/chat endpoint, checks queued AI messages or receipts, or needs cross-AI coordination without manual copy-paste.
---

# AI Messenger

Use one durable broker at `C:\Repos\ai-messenger`. Do not create a project-specific mailbox,
Bossman dependency, or ad hoc thread-message loop.

## Start safely

1. Run `python C:\Users\zev\.codex\skills\ai-messenger\scripts\messenger.py gateway-status`.
   The authoritative database is
   `%LOCALAPPDATA%\ZDH\ai-messenger\ai-messenger.db`, outside OneDrive and project repos.
2. Identify the exact named project channel and its workspace root.
3. Use an endpoint already bound to that channel, or register and bind a new exact endpoint.
4. Queue one bounded message with a correlation ID and expected typed return.
5. Run `python C:\Users\zev\.codex\skills\ai-messenger\scripts\messenger.py gateway-plan-next`
   and inspect the destination before any send.

Never route a project through an unrelated Codex task merely because that task is open. Each Codex
endpoint needs its own session ID and matching project workspace.

## Register a project task

Register the exact Codex endpoint first, then give the project a persistent Claude endpoint:

```powershell
python C:\Users\zev\.codex\skills\ai-messenger\scripts\messenger.py register-claude-project `
  --channel PROJECT-SLUG `
  --project PROJECT-SLUG `
  --workspace-root "ABSOLUTE_PROJECT_ROOT" `
  --source-endpoint EXISTING-CODEX-ENDPOINT `
  --claude-endpoint claude-PROJECT-SLUG `
  --session-name "ZDH - PROJECT NAME"
```

This creates no chat traffic. The first queued delivery creates the named Claude session; later
deliveries resume the exact session UUID.

Prefer one registered ChatGPT Desktop Work mailbox endpoint with `existing_only=true` and
`create_if_missing=false`. Register browser fallbacks by exact conversation URL, never by tab
number or title. A ChatGPT browser URL must contain `/c/`; a DeepSeek URL must contain
`/a/chat/s/`.

## Queue work

```powershell
python C:\Users\zev\.codex\skills\ai-messenger\scripts\messenger.py enqueue --channel PROJECT-SLUG --source SOURCE-ENDPOINT --target TARGET-ENDPOINT --correlation-id STABLE-ID --idempotency-key STABLE-KEY --body "BOUNDED TASK AND RETURN REQUIREMENTS"
python C:\Users\zev\.codex\skills\ai-messenger\scripts\messenger.py gateway-plan-next
```

Repeated work must reuse an explicit `--idempotency-key`. Keep `max_rounds` at 2 unless Zev
approves more. Do not include credentials, private browser history, or unrelated files.

## Provider rules

- **Codex:** target a saved project task by session ID. Do not resume an actively writing task.
- **Claude Code:** target a `claude_gateway_session`. The hidden gateway creates or resumes one
  named session per project, defaults to plan/read-only authority, and validates a typed receipt
  locally.
- **Claude Desktop:** treat it as unaddressable until its local adapter registers a real listener.
- **ChatGPT Desktop:** use `$chatgpt-desktop-bridge` and endpoint `chatgpt-design-desktop` for the
  exact existing `Design Studio` conversation. Its active kind is `chatgpt_desktop_uia`; do not
  reactivate the retired file-mailbox experiment. The endpoint must remain exact-title,
  existing-only, one-round, and typed-receipt validated.
- **ChatGPT/DeepSeek Chrome:** use the existing exact-URL bridge only as an explicit fallback.

The gateway itself must remain running as the hidden `ZDH Claude Gateway` task. Individual Claude
processes may be idle. During provider or network interruption, leave messages queued and report
`degraded/recovering`; never create repeated workers or visible shell windows to wake it.

## Gates

- Never install startup, enable a new write-capable route, or run the first live provider smoke test
  without Commander approval. Existing approved read-only project routes may enqueue bounded work.
- Use `kill-switch on` for wrong routing, popup/noise regression, duplicate delivery, or unsafe state.
- Accept a receipt only when its message/channel/project/correlation/attempt IDs and Claude session
  ID match the durable dispatch.
- Keep one in-flight delivery per endpoint/channel pair.

Read [references/protocol.md](references/protocol.md) when adding an adapter, changing state
transitions, or diagnosing a stuck delivery.
