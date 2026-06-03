---
name: chatgpt-routing
description: Use when deciding whether to route non-code work out of Codex to ChatGPT to preserve Codex usage, preparing or importing a ChatGPT handoff, or distinguishing ChatGPT writing/strategy/design direction work from Codex repo execution.
---

# ChatGPT Routing

Use this skill when a task can be completed without Codex-specific tools or local repo execution.

## Route To ChatGPT

Route to ChatGPT when the task is mainly:

- Brainstorming, naming, ideation, option generation, or second opinions.
- Emails, posts, sales copy, internal comms, tone rewrites, or user-facing copy.
- Strategy, learning, explanations, critiques, outlines, or planning.
- Meeting summaries, rough research synthesis, simple classification, or non-code notes.
- Graphic design direction, moodboards, layout concepts, ad/poster/social concepts, image prompts, color/type exploration, or design critique when no local asset editing is needed.

Say:

`ChatGPT route recommended - brief reason`

Then prepare the handoff:

`C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`

## Keep In Codex

Keep the task in Codex when it needs:

- Local files, repo context, terminal commands, tests, builds, git, commits, pushes, PRs, deploys, logs, screenshots, or browser/app verification.
- Durable changes to `C:\Users\zev\.codex`, systems backup, project dashboards, scripts, skills, hooks, or workflows.
- Owner-button queue state or an active Codex goal.
- Actual asset generation or editing, local design files, web/app UI implementation, screenshot QA, brand systems, production deliverables, or real-person face work requiring exact pixel preservation.
- Auth, billing, security, database, permissions, production risk, or ambiguous failures. Use xhigh/council; ChatGPT can give a second opinion, but Codex executes only after guardrails.

## Return To Codex

Routed prompts should require ChatGPT to end with a `CODEX_RETURN_PACKET` containing summary, decisions, deliverable, Codex next action, files/assets needed, and owner buttons needed.

After Zev copies the ChatGPT answer and says `import ChatGPT result`, import it with:

`C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print`

Then continue the Codex mission from the imported packet without asking Zev to repeat context.

## Boundary

Do not claim the current Codex Desktop chat has switched to ChatGPT. The current session can dispatch or prepare the prompt; the routed work happens in ChatGPT or another non-Codex model surface.

If API-based ChatGPT routing is requested, use `Commander approval needed` before adding it because it may require API key setup, billing, model choice, and data-sharing decisions.
