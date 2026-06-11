---
name: chatgpt-routing
description: Use when deciding whether to route non-code work out of Codex to ChatGPT to preserve Codex usage, preparing or importing a ChatGPT handoff, or distinguishing ChatGPT writing/strategy/design direction work from Codex repo execution.
---

# ChatGPT Routing

Use this skill when a task can be completed without Codex-specific tools or local repo execution.

For Zev's projects, also use `$codex-chatgpt-bridge` when the task involves preserving Codex credits, preparing a bounded handoff, or importing a structured return packet.

## Route To ChatGPT

Route to ChatGPT when the task is mainly:

- Brainstorming, naming, ideation, option generation, or second opinions.
- Emails, posts, sales copy, internal comms, tone rewrites, or user-facing copy.
- Strategy, learning, explanations, critiques, outlines, or planning.
- Meeting summaries, rough research synthesis, simple classification, or non-code notes.
- Graphic design direction, moodboards, layout concepts, ad/poster/social concepts, image prompts, color/type exploration, or design critique when no local asset editing is needed.

Say:

`ChatGPT route recommended - brief reason`

Then prepare the handoff, or let the optimizer do it:

`C:\Users\zev\.codex\scripts\codex-gateway.cmd -DryRun "TASK"`

`C:\Users\zev\.codex\scripts\codex-gateway.cmd "TASK"`

`C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`

`C:\Users\zev\.codex\scripts\ai-credits-optimizer.cmd "TASK"`

`codex-gateway.cmd` is the preferred front door. It reuses exact cached ChatGPT packets/assets when safe, bypasses cache for freshness-sensitive prompts, and logs route/savings events. Use `-Refresh` for a new ChatGPT run, `-NoCache` for raw routing tests, and `-SplitHybrid` only when the detachable ChatGPT subtask is clear. Use `codex-gateway-tally.cmd` to inspect route counts, ChatGPT moves, savings estimates, and the reason/signals behind each decision. `codex-auto.cmd` also runs the lower-level optimizer before launching a new Codex session. Use `[codex]`, `--codex`, or `-ForceCodex` to bypass the optimizer when the task should stay in Codex.

## Keep In Codex

Keep the task in Codex when it needs:

- Local files, repo context, terminal commands, tests, builds, git, commits, pushes, PRs, deploys, logs, screenshots, or browser/app verification.
- Durable changes to `C:\Users\zev\.codex`, systems backup, project dashboards, scripts, skills, hooks, or workflows.
- Owner-button queue state or an active Codex goal.
- Actual local asset generation or editing, local design files, web/app UI implementation, screenshot QA, brand systems, production deliverables, or real-person face work requiring exact pixel preservation, unless Zev explicitly asks ChatGPT to be the image surface; then orchestrate ChatGPT end to end.
- Auth, billing, security, database, permissions, production risk, or ambiguous failures. Use xhigh/council; ChatGPT can give a second opinion, but Codex executes only after guardrails.

## Return To Codex

Routed prompts should require ChatGPT to end with a `CODEX_RETURN_PACKET` containing summary, decisions, deliverable, Codex next action, files/assets needed, and owner buttons needed.

Default to full automation when Chrome/ChatGPT web is available:

- Open or claim the ChatGPT tab with the Chrome browser plugin.
- Submit the routed prompt directly.
- Wait for completion.
- Copy/import text results or download generated image assets.
- Save generated images to the project assets folder when one is obvious, otherwise to `C:\Users\zev\OneDrive\Documents\ZDH Generated Assets`.
- Visually inspect downloaded images before finalizing.

Use manual clipboard return only when browser automation is unavailable or ChatGPT requires a true owner-only action such as login, CAPTCHA, payment, account verification, or safety confirmation.

After Zev copies the ChatGPT answer and says `import ChatGPT result`, import it with:

`C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print -RequirePacket`

Then continue the Codex mission from the imported packet without asking Zev to repeat context.

After useful or bad routes, record quality with:

`C:\Users\zev\.codex\scripts\codex-gateway-feedback.cmd -SessionPath "SESSION_JSON" -Rating 1-5 -Outcome good|mixed|bad -Notes "..."`

## Boundary

Do not claim the current Codex Desktop chat has switched to ChatGPT. The current session can dispatch or prepare the prompt; the routed work happens in ChatGPT or another non-Codex model surface.

If API-based ChatGPT routing is requested, use `Commander approval needed` before adding it because it may require API key setup, billing, model choice, and data-sharing decisions.

## Future Projects

To make a project carry these rules explicitly, run:

`C:\Users\zev\.codex\scripts\codex-project-rules.cmd`

The script creates or updates a marked Zev workflow block in the project `AGENTS.md` while preserving local project-specific rules.
