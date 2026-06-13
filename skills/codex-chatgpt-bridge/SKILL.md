---
name: codex-chatgpt-bridge
description: Route detachable non-repo work from Codex to ChatGPT or DeepSeek and import structured return packets to preserve Codex credits. Use when deciding whether to ask ChatGPT for premium writing/creative/strategy work, DeepSeek for low-cost first-pass/volume drafts, preparing a bounded handoff, importing a CODEX_RETURN_PACKET, or hardening the Codex/provider bridge.
---

# Codex ChatGPT Bridge

Use this skill to spend Codex only where Codex is uniquely useful: local files, tools, tests, git, app connectors, verification, and production-sensitive work. ChatGPT and DeepSeek are detachable provider lanes; Codex remains the conductor.

## Workflow

1. Classify the request before doing substantial work.
   - Route to ChatGPT when the work is detachable thinking: writing, copy, brainstorming, naming, strategy, summaries, explanations, research synthesis, translation, design direction, critique, or ChatGPT-native image/logo generation that does not require local editing.
   - Route to DeepSeek when the work is a low-cost first pass: bulk drafts, SEO article packets, long-form rough drafts, alternate/comparison drafts, cheap second opinions, or volume work that Codex will QA before publishing.
   - Keep in Codex when the work needs local files, repo state, terminal commands, tests, git, deployment, browser/app verification, connectors, inboxes, owner-button state, secrets, auth, billing, database, security, permissions, or production judgment.
2. For new CLI/automation work, prefer the optimizer:
   `C:\Users\zev\.codex\scripts\ai-provider-gateway.cmd -DryRun "TASK"`
   Dispatch through the provider gateway with:
   `C:\Users\zev\.codex\scripts\ai-provider-gateway.cmd "TASK"`
3. The ChatGPT-specific gateway remains available:
   `C:\Users\zev\.codex\scripts\codex-gateway.cmd -DryRun "TASK"`
   Dispatch through the ChatGPT gateway with:
   `C:\Users\zev\.codex\scripts\codex-gateway.cmd "TASK"`
4. The lower-level optimizer remains available for Codex profile launches:
   `C:\Users\zev\.codex\scripts\ai-credits-optimizer.cmd -DryRun "TASK"`
5. If routing away manually, use:
   `C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`
   or:
   `C:\Users\zev\.codex\scripts\deepseek-route.cmd "TASK"`
   For the one-command session/log helper, use:
   `C:\Users\zev\.codex\scripts\chatgpt-auto-route.cmd -Project "PROJECT" -OutDir "OUTPUT_DIR" "TASK"`
6. When a provider returns, import text packets with:
   `C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print -RequirePacket`
7. Codex resumes only the local/verification/execution part from the packet.

## Auto Bridge Helper

Use `ai-provider-gateway.cmd` as the provider-aware front door. It classifies tasks as `codex`, `chatgpt`, `deepseek`, or `hybrid`.

- ChatGPT is the premium lane for polished writing, emails, sales copy, strategy, positioning, explanations, summaries, high-quality creative direction, brand work, and ChatGPT-native image/logo generation.
- DeepSeek is the low-cost lane for first-pass drafts, bulk/volume long-form content, SEO article packets, rough structured analysis, comparison drafts, and cheap second opinions.
- Hybrid means the external provider drafts or thinks, then Codex imports, applies, verifies, publishes, or tests locally.

Use `codex-gateway.cmd` as the front door. It classifies tasks as `chatgpt`, `codex`, or `hybrid`; auto-dispatches pure ChatGPT tasks to `chatgpt-auto-route.cmd`; dispatches pure local work to `codex-auto.cmd`; and marks mixed work as ask-first so Codex can split the detachable part without losing the local execution half.

The gateway also acts like a small AI control plane:

- Exact completed ChatGPT results are cached by project plus normalized task. A cache hit returns the prior `CODEX_RETURN_PACKET` and asset paths without spending a fresh Codex or ChatGPT run.
- Cache is bypassed automatically for freshness-sensitive prompts such as latest/current/today/news/price/weather/schedule. Use `-Refresh` to force a new ChatGPT run and `-NoCache` when testing the raw bridge.
- Dry runs show route, confidence, cache status, heuristic avoided-Codex token estimate, and current Codex rate-limit pressure when session telemetry is available.
- Hybrid tasks stay ask-first by default. Use `-SplitHybrid` only when the detachable ChatGPT part is clear and Codex should prepare that subtask before applying/verifying locally after return.
- Use `codex-gateway-tally.cmd` to see a running ledger of ChatGPT and DeepSeek route decisions, why each route was chosen, cache status, actual dispatches/completions, and estimated avoided Codex usage.
- Record quality signals with `codex-gateway-feedback.cmd -SessionPath "SESSION_JSON" -Rating 1-5 -Outcome good|mixed|bad -Notes "..."`.

Use `chatgpt-auto-route.cmd` for repeatable bridge runs. It routes the task, creates a session log, writes the ChatGPT prompt to a file, copies it to the clipboard, opens ChatGPT unless `-NoOpen` is set, and prints the Codex Desktop Chrome runner snippet.

In Codex Desktop, run the printed snippet with the Node REPL tool to submit the prompt through Chrome, wait for completion, bundle generated page images, save them under the requested output folder, write/import the return packet, and append a savings event to `.codex/logs/chatgpt-bridge/events.jsonl`.

Important limitation: the PowerShell command cannot directly call the Codex Chrome extension outside a Codex Desktop tool runtime. The Chrome automation layer lives in `chatgpt-chrome-bridge.mjs` and must run from Codex Desktop where the `agent.browsers` API exists.

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
- Force DeepSeek: `-ForceDeepSeek`, `[deepseek]`, or `--deepseek`.
- Bypass the optimizer only for testing raw gear routing: `-NoOptimizeCredits`.

## Reference

Read `references/routing-taxonomy.md` when tuning routing rules or deciding edge cases.
