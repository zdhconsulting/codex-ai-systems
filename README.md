# Codex AI Systems

Personal Codex workflow tools for Zev.

This repo is intentionally separate from project-specific repos. It stores reusable Codex workflow instructions, safety guards, reasoning profiles, and owner-button tooling.

## What This Solves

- Keeps Codex workflow rules out of website/client repos.
- Makes owner-only blockers visible in one queue.
- Prevents accidental commits/pushes to the wrong repo.
- Gives Codex low/medium/high/xhigh model and reasoning profiles.
- Makes setup portable to another machine.

## Contents

- `instructions/AGENTS.md`: global Codex breadcrumb.
- `skills/owner-button-workflow/`: reusable Codex skill.
- `scripts/codex-auto.cmd`: auto-selects reasoning gear for CLI tasks.
- `scripts/codex-bounce.cmd`: runs xhigh self-bounce preflight only.
- `scripts/codex-doctor.cmd`: runs the local systems health check.
- `scripts/codex-gear.cmd`: shows which model/profile a task will use.
- `scripts/codex-gear-test.cmd`: verifies profile files, forced commands, route selection, and optional real smoke tests.
- `scripts/codex-systems-status.cmd`: shows current repo, owner buttons, gear routes, and systems backup state.
- `scripts/codex-low.cmd`, `codex-medium.cmd`, `codex-high.cmd`, `codex-xhigh.cmd`, `codex-xhigh-bounce.cmd`, `codex-review.cmd`: force a specific model/profile route.
- `scripts/codex-handoff.cmd`: creates a portable handoff note for another Codex or computer.
- `scripts/owner-button.cmd`: lists/adds/completes owner-only blockers.
- `scripts/git-guard.cmd`: checks repo, branch, remote, dirty files before git/deploy actions.
- `profiles/*.config.toml`: Codex reasoning profiles.
- `queues/owner-buttons.example.json`: empty queue template.
- `dashboard/`: ZDH Dashboard source for project, git, and owner-button monitoring.
- `codexui/`: standalone Codex custom UI prototype and launcher source.

## Install

From this repo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## Common Commands

Run the local systems health check:

```powershell
.\scripts\codex-doctor.cmd
.\scripts\codex-doctor.cmd -Smoke
```

Auto-route a Codex task:

```powershell
.\scripts\codex-auto.cmd "fix the mobile nav"
```

Dry-run the routing decision:

```powershell
.\scripts\codex-auto.cmd -DryRun "debug failing CI"
```

Inspect the model/profile route:

```powershell
.\scripts\codex-gear.cmd "debug failing CI"
```

Verify the installed gear setup:

```powershell
.\scripts\codex-gear-test.cmd
.\scripts\codex-gear-test.cmd -Smoke
```

Show current repo, owner buttons, gear routes, and systems backup state:

```powershell
.\scripts\codex-systems-status.cmd
```

Force a specific model/profile route:

```powershell
.\scripts\codex-low.cmd "fix typo in README"
.\scripts\codex-medium.cmd "add dashboard panel"
.\scripts\codex-high.cmd "debug failing tests"
.\scripts\codex-xhigh.cmd "change auth permissions"
.\scripts\codex-xhigh-bounce.cmd "change auth permissions"
.\scripts\codex-review.cmd "review current diff"
```

Run xhigh self-bounce without implementation:

```powershell
.\scripts\codex-bounce.cmd "plan database migration safely"
```

## Gear Model Plan

- `low` / `fast`: `gpt-5.3-codex-spark`, low reasoning, for ultra-fast simple coding and mechanical tasks.
- `medium` / `balanced`: `gpt-5.4`, medium reasoning, for normal implementation work.
- `high` / `deep`: `gpt-5.5`, high reasoning, for debugging, CI, regressions, multi-file work, deploy issues, and verification-heavy tasks.
- `xhigh` / `max`: `gpt-5.5`, xhigh reasoning, for architecture, auth, security, billing, database, permissions, and production-risk work.
- `review`: `codex-auto-review`, medium reasoning, for explicit code review, PR review, diff review, or commit review.

Self-bounce is available for xhigh work. It runs a read-only ephemeral preflight where Builder, Skeptic, and Verifier compare approaches before implementation starts.

`gpt-5.4-mini` is available but not used by default; keep it as a low/medium fallback if Spark is too shallow or unavailable.

Create a handoff note for another Codex:

```powershell
.\scripts\codex-handoff.cmd
```

List owner-only blockers:

```powershell
.\scripts\owner-button.cmd list
```

Check the current repo before commit/push:

```powershell
.\scripts\git-guard.cmd
```

Run the dashboard from source:

```powershell
& ".\dashboard\Start ZDH Dashboard.bat"
```

Run the custom Codex UI prototype:

```powershell
cd .\codexui
python .\server.py
```

Sync the live Codex setup into this repo, commit, and push:

```powershell
.\scripts\save-codex-systems.cmd
```

## GitHub Remote Setup

If this repo is only local, create a GitHub repo named `codex-ai-systems`, then run:

```powershell
git remote add origin https://github.com/zdhconsulting/codex-ai-systems.git
git push -u origin main
```

After that, Codex can run `C:\Users\zev\.codex\scripts\save-codex-systems.cmd` after workflow changes to auto-save them to GitHub.
