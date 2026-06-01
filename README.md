# Codex AI Systems

Personal Codex workflow tools for Zev.

This repo is intentionally separate from project-specific repos. It stores reusable Codex workflow instructions, safety guards, reasoning profiles, and owner-button tooling.

## What This Solves

- Keeps Codex workflow rules out of website/client repos.
- Makes owner-only blockers visible in one queue.
- Prevents accidental commits/pushes to the wrong repo.
- Gives Codex low/medium/high/xhigh reasoning profiles.
- Makes setup portable to another machine.

## Contents

- `instructions/AGENTS.md`: global Codex breadcrumb.
- `skills/owner-button-workflow/`: reusable Codex skill.
- `scripts/codex-auto.cmd`: auto-selects reasoning gear for CLI tasks.
- `scripts/owner-button.cmd`: lists/adds/completes owner-only blockers.
- `scripts/git-guard.cmd`: checks repo, branch, remote, dirty files before git/deploy actions.
- `profiles/*.config.toml`: Codex reasoning profiles.
- `queues/owner-buttons.example.json`: empty queue template.

## Install

From this repo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## Common Commands

Auto-route a Codex task:

```powershell
.\scripts\codex-auto.cmd "fix the mobile nav"
```

Dry-run the routing decision:

```powershell
.\scripts\codex-auto.cmd -DryRun "debug failing CI"
```

List owner-only blockers:

```powershell
.\scripts\owner-button.cmd list
```

Check the current repo before commit/push:

```powershell
.\scripts\git-guard.cmd
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
