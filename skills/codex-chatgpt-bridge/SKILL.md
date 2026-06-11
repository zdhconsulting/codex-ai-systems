---
name: codex-chatgpt-bridge
description: Route detachable non-repo work from Codex to ChatGPT and import structured return packets to preserve Codex credits. Use when deciding whether to ask ChatGPT for writing, brainstorming, strategy, summaries, research synthesis, translation, design direction, or second opinions; preparing a bounded ChatGPT handoff; importing a CODEX_RETURN_PACKET; or hardening the Codex/ChatGPT usage bridge.
---

# Codex ChatGPT Bridge

Use this skill to spend Codex only where Codex is uniquely useful: local files, tools, tests, git, app connectors, verification, and production-sensitive work.

## Workflow

1. Classify the request before doing substantial work.
   - Route to ChatGPT when the work is detachable thinking: writing, copy, brainstorming, naming, strategy, summaries, explanations, research synthesis, translation, design direction, critique, or ChatGPT-native image/logo generation that does not require local editing.
   - Keep in Codex when the work needs local files, repo state, terminal commands, tests, git, deployment, browser/app verification, connectors, inboxes, owner-button state, secrets, auth, billing, database, security, permissions, or production judgment.
2. For new CLI/automation work, prefer the optimizer:
   `C:\Users\zev\.codex\scripts\ai-credits-optimizer.cmd -DryRun "TASK"`
3. If routing away, use:
   `C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`
4. When ChatGPT returns, import with:
   `C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print -RequirePacket`
5. Codex resumes only the local/verification/execution part from the packet.

## Handoff Rules

- Ask ChatGPT for bounded output, not open-ended agent work.
- Do not send private account contents, secrets, tokens, unpublished sensitive data, or local file paths unless the user explicitly provided the text for that purpose.
- If Zev asks ChatGPT to make actual images/logos, the handoff should tell ChatGPT to generate the image asset, not merely describe concepts. Codex should then download/save/inspect the output.
- Only invent client names, facts, examples, or proof when Zev explicitly says the work is fictional, made up, sample, mock, placeholder, or a test.
- Ask ChatGPT to admit when the task should return to Codex.
- Require a `CODEX_RETURN_PACKET` with Summary, Decisions, Deliverable, Codex next action, Files/assets needed, Owner buttons needed, Confidence, and Go back to Codex?.
- Prefer `-PacketOnly` when the result is meant mainly for Codex to consume.

## Overrides

- Force Codex: `-ForceCodex`, `[codex]`, or `--codex`.
- Force ChatGPT: `-ForceChatGPT`, `[chatgpt]`, or `--chatgpt`.
- Bypass the optimizer only for testing raw gear routing: `-NoOptimizeCredits`.

## Reference

Read `references/routing-taxonomy.md` when tuning routing rules or deciding edge cases.
