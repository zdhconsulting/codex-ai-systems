# Project State

Last updated: 2026-06-14

## Project

AI Manager is a conductor worker inside the `codex-ai-systems` repo. Its job is to watch important projects, decide whether they are running, explain why they are not running, report the situation clearly, and make bounded changes when the fix is safe and explicitly configured.

## Active Mission

Build the smallest useful manager loop: inspect configured projects, report status and failure reasons, then prepare safe repair hooks.

## Current Source Of Truth

- Repo home: `C:\Repos\codex-ai-systems`
- Project instructions: `AGENTS.md`
- Intake questions: `planning/intake.md`
- Requirements draft: `planning/requirements.md`
- Blueprint: `planning/blueprint.md`
- First command: `scripts/ai-manager.cmd`

## Working Rules

- Keep AI Manager files inside `ai-manager/` until integration is explicitly requested.
- Record durable decisions in `planning/decisions.md` once decisions exist.
- Prefer a small working prototype over a broad speculative architecture.
- AI Manager can report aggressively, but should only change files, processes, or deployments through explicit safe actions or normal Codex approval gates.

## Next Useful Actions

- Run the first manager report from `C:\Repos\codex-ai-systems`.
- Copy `projects.example.json` to gitignored `projects.local.json` and add Zev's real project paths.
- Add safe fix commands for low-risk recoveries, such as regenerating a status report or rerunning a local health check.
- Decide whether the next interface should be a dashboard panel, scheduled worker, or Codex `Next` integration.

## Blockers

- Real project inventory is not configured yet.

## Recent Verification

- 2026-06-14: Created isolated AI Manager planning scaffold.
- 2026-06-14: Moved scaffold into `C:\Repos\codex-ai-systems\ai-manager` for GitHub home `zdhconsulting/codex-ai-systems`.
- 2026-06-14: Confirmed AI Manager is a conductor worker for all projects.
