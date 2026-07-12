---
name: chatgpt-desktop-bridge
description: Route bounded creative, research, writing, image, or design work from Codex to one registered existing ChatGPT Chat/Work conversation in the same desktop app without opening Chrome. Use when Zev says to have ChatGPT do something, asks for ChatGPT graphic design or custom icons, targets a specific current ChatGPT project/conversation, or asks Codex to import the result and continue local implementation.
---

# ChatGPT Desktop Bridge

Use AI Messenger as the source of truth. This skill never drives Chrome, injects into private app
state, or silently creates a ChatGPT conversation.

## Route Work

1. Keep code, repo changes, tests, git, deployment, and final QA in Codex.
2. Route detachable creative work to a registered ChatGPT desktop endpoint: graphic design, custom
   icon concepts, image generation, moodboards, polished copy, research, or critique.
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

Run `setup`, then give the existing ChatGPT Work conversation the listener contract at
`references/listener-contract.md`. After it writes the challenge-matching acknowledgement and Zev
confirms the standing route, run `activate --approve-live`. This is a one-time attachment, not a new
conversation per request.

## Fail Closed

- Never claim that sharing one desktop app creates a direct Codex-to-ChatGPT task API.
- Never use keyboard simulation, private app databases, generated conversation IDs, or tab order.
- Never cross project channels without an explicit endpoint binding.
- Never accept artifacts outside the endpoint mailbox's `artifacts` directory.
- Never run an unbounded AI-to-AI loop; the channel's maximum rounds still applies.
