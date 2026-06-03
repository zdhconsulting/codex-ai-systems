---
name: chatgpt-routing
description: Use when deciding whether to route non-code work out of Codex to ChatGPT to preserve Codex usage, preparing a ChatGPT handoff prompt, or distinguishing ChatGPT writing/strategy work from Codex repo execution.
---

# ChatGPT Routing

Use this skill when a task can be completed without Codex-specific tools or local repo execution.

## Route To ChatGPT

Route to ChatGPT when the task is mainly:

- Brainstorming, naming, ideation, option generation, or second opinions.
- Emails, posts, sales copy, internal comms, tone rewrites, or user-facing copy.
- Strategy, learning, explanations, critiques, outlines, or planning.
- Meeting summaries, rough research synthesis, simple classification, or non-code notes.

Say:

`ChatGPT route recommended - brief reason`

Then prepare the handoff:

`C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`

## Keep In Codex

Keep the task in Codex when it needs:

- Local files, repo context, terminal commands, tests, builds, git, commits, pushes, PRs, deploys, logs, screenshots, or browser/app verification.
- Durable changes to `C:\Users\zev\.codex`, systems backup, project dashboards, scripts, skills, hooks, or workflows.
- Owner-button queue state or an active Codex goal.
- Auth, billing, security, database, permissions, production risk, or ambiguous failures. Use xhigh/council; ChatGPT can give a second opinion, but Codex executes only after guardrails.

## Boundary

Do not claim the current Codex Desktop chat has switched to ChatGPT. The current session can dispatch or prepare the prompt; the routed work happens in ChatGPT or another non-Codex model surface.

If API-based ChatGPT routing is requested, use `Commander approval needed` before adding it because it may require API key setup, billing, model choice, and data-sharing decisions.
