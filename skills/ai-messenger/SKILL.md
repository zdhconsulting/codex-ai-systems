---
name: ai-messenger
description: Route bounded, typed work between a named Codex project task and specific Claude, ChatGPT, DeepSeek, or Codex endpoints through the PC-local AI Messenger. Use when Zev asks one AI chat to speak to another, asks a project to use the bridge, registers a new project/chat endpoint, checks queued AI messages or receipts, or needs cross-AI coordination without manual copy-paste.
---

# AI Messenger

Use one durable broker at `C:\Repos\ai-messenger`. Do not create a project-specific mailbox,
Bossman dependency, or ad hoc thread-message loop.

## Start safely

1. Run `python scripts/messenger.py status`.
2. Identify the exact named project channel and its workspace root.
3. Use an endpoint already bound to that channel, or register and bind a new exact endpoint.
4. Queue one bounded message with a correlation ID and expected typed return.
5. Run `python scripts/messenger.py plan-next` and inspect the destination before any send.

Never route a project through an unrelated Codex task merely because that task is open. Each Codex
endpoint needs its own session ID and matching project workspace.

## Register a project task

```powershell
python scripts/messenger.py add-channel --channel PROJECT-SLUG --project PROJECT-SLUG --workspace-root "ABSOLUTE_PROJECT_ROOT" --authority read_only --max-rounds 2
python scripts/messenger.py add-endpoint --endpoint ENDPOINT-ID --provider codex --kind codex_cli_session --address-json '{"session_id":"TASK_ID","cwd":"ABSOLUTE_PROJECT_ROOT","executable":"C:\\Users\\zev\\AppData\\Local\\OpenAI\\Codex\\bin\\a7c12ebff69fb123\\codex.exe"}' --status ready
python scripts/messenger.py bind --channel PROJECT-SLUG --endpoint ENDPOINT-ID --role coordinator
```

Prefer one registered ChatGPT Desktop Work mailbox endpoint with `existing_only=true` and
`create_if_missing=false`. Register browser fallbacks by exact conversation URL, never by tab
number or title. A ChatGPT browser URL must contain `/c/`; a DeepSeek URL must contain
`/a/chat/s/`.

## Queue work

```powershell
python scripts/messenger.py enqueue --channel PROJECT-SLUG --source SOURCE-ENDPOINT --target TARGET-ENDPOINT --correlation-id STABLE-ID --body "BOUNDED TASK AND RETURN REQUIREMENTS"
python scripts/messenger.py plan-next --provider PROVIDER
```

Repeated work must reuse an explicit `--idempotency-key`. Keep `max_rounds` at 2 unless Zev
approves more. Do not include credentials, private browser history, or unrelated files.

## Provider rules

- **Codex:** target a saved project task by session ID. Do not resume an actively writing task.
- **Claude Code:** target a managed CLI session ID. Default to plan/read-only authority.
- **Claude Desktop:** treat it as unaddressable until its local adapter registers a real listener.
- **ChatGPT Desktop:** use `$chatgpt-desktop-bridge` with a challenge-acknowledged existing Work
  conversation. Require typed mailbox receipts and never open or create another conversation.
- **ChatGPT/DeepSeek Chrome:** use the existing exact-URL bridge only as an explicit fallback.

If a provider is offline, leave the message queued. Do not create repeated workers or visible shell
windows to wake it.

## Gates

- Never run `live-gate on` without Commander approval for the bounded smoke test.
- Use `kill-switch on` for wrong routing, popup/noise regression, duplicate delivery, or unsafe state.
- Accept a receipt only when its `message_id` and `correlation_id` match the queued message.
- Keep one in-flight delivery per endpoint/channel pair.

Read [references/protocol.md](references/protocol.md) when adding an adapter, changing state
transitions, or diagnosing a stuck delivery.
