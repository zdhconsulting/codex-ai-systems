---
name: chatgpt-desktop-bridge
description: Prepare, inspect, or troubleshoot a Chrome-free handoff from Codex to a registered existing ChatGPT Chat/Work conversation, and use it only when a supported write-capable endpoint is ready. Use when Zev asks whether desktop ChatGPT can receive work, targets a specific ChatGPT project/conversation, or needs the current desktop bridge status and safe fallback.
---

# ChatGPT Desktop Bridge

Use AI Messenger as the source of truth. This skill never drives Chrome, injects into private app
state, or silently creates a ChatGPT conversation.

## Current Status

The file-only ChatGPT Work listener is **not operational on this setup**. ChatGPT Work declined the
local write and required a Codex handoff, so `chatgpt-design-desktop` is `unaddressable`. Do not
activate or publish to it until an official native cross-mode tool or an approved write-capable app
proves a real receipt round trip.

## Route Work

1. Keep code, repo changes, tests, git, deployment, and final QA in Codex.
2. Route detachable creative work to a registered ChatGPT desktop endpoint only when its status is
   `ready` and its transport has passed a live round trip.
3. Resolve the exact endpoint alias. Require `existing_only=true` and `create_if_missing=false`.
4. If the endpoint is absent, offline, or unacknowledged, queue the request and report the one-time
   listener setup. Do not fall back to Chrome unless Zev explicitly asks.
5. Import only a typed receipt whose message, correlation, endpoint, and artifact paths validate.
6. Inspect returned assets before integrating them locally.

## Commands

Use the deterministic helper:

```powershell
python C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\bridge.py status `
  --endpoint chatgpt-design-desktop

python C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\bridge.py send `
  --channel ai-messenger-control `
  --source codex-cto-current `
  --target chatgpt-design-desktop `
  --body "Create six custom icon concepts and return the assets."

python C:\Users\zev\.codex\skills\chatgpt-desktop-bridge\scripts\bridge.py receive `
  --endpoint chatgpt-design-desktop
```

`send` queues safely. Add `--publish` only when the endpoint is ready, its standing live approval
is true, and AI Messenger's live gate is on.

## Attach One Existing Work Conversation

The `setup` and `activate` commands are retained for a future supported listener. Do not ask Zev to
repeat the failed folder attachment on the current Work surface.

## Fail Closed

- Never claim that sharing one desktop app creates a direct Codex-to-ChatGPT task API.
- Never use keyboard simulation, private app databases, generated conversation IDs, or tab order.
- Never cross project channels without an explicit endpoint binding.
- Never accept artifacts outside the endpoint mailbox's `artifacts` directory.
- Never run an unbounded AI-to-AI loop; the channel's maximum rounds still applies.
