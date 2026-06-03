# Codex AI Systems

Personal Codex workflow tools for Zev.

This repo is intentionally separate from project-specific repos. It stores reusable Codex workflow instructions, safety guards, reasoning profiles, and owner-button tooling.

## What This Solves

- Keeps Codex workflow rules out of website/client repos.
- Makes owner-only blockers visible in one queue.
- Prevents accidental commits/pushes to the wrong repo.
- Gives Codex low/medium/high/xhigh model and reasoning profiles.
- Makes setup portable to another machine.
- Gives new users a browsable catalog and installable skill packs.

## Contents

- `instructions/AGENTS.md`: global Codex breadcrumb.
- `catalog/`: static Skill Catalog site for new users.
- `packs/manifest.json`: installable pack definitions.
- `skills/`: reusable Codex skills, including `owner-button-workflow`.
- `scripts/chatgpt-route.cmd` and `scripts/chatgpt-return.cmd`: route non-repo work to ChatGPT and import the result back into Codex.
- `scripts/codex-auto.cmd`: auto-selects reasoning gear for CLI tasks.
- `scripts/codex-bounce.cmd`: runs xhigh self-bounce preflight only.
- `scripts/codex-council.cmd`: runs the CEO/CTO/Programmer/QA xhigh workflow.
- `scripts/codex-doctor.cmd`: runs the local systems health check.
- `scripts/codex-gear.cmd`: shows which model/profile a task will use.
- `scripts/codex-gear-test.cmd`: verifies profile files, forced commands, route selection, and optional real smoke tests.
- `scripts/codex-project-freshness.cmd`: colors saved Codex project markers by last modified age.
- `scripts/codex-systems-status.cmd`: shows current repo, owner buttons, gear routes, and systems backup state.
- `scripts/codex-low.cmd`, `codex-medium.cmd`, `codex-high.cmd`, `codex-xhigh.cmd`, `codex-xhigh-bounce.cmd`, `codex-xhigh-raw.cmd`, `codex-council.cmd`, `codex-review.cmd`: force a specific model/profile route.
- `scripts/codex-handoff.cmd`: creates a portable handoff note for another Codex or computer.
- `scripts/owner-button.cmd`: lists/adds/completes owner-only blockers.
- `scripts/git-guard.cmd`: checks repo, branch, remote, dirty files before git/deploy actions.
- `profiles/*.config.toml`: Codex reasoning profiles.
- `queues/owner-buttons.example.json`: empty queue template.
- `dashboard/`: ZDH Dashboard source for project, git, and owner-button monitoring.
- `codexui/`: standalone Codex custom UI prototype and launcher source.

## Save

Sync the live Codex setup into this repo, commit, and push:

```powershell
C:\Users\zev\.codex\scripts\save-codex-systems.cmd
```

This saves the portable AI operating system: global instructions, reasoning profiles, scripts, non-system skills, owner-button workflow, dashboard tooling, and import instructions.

It intentionally does not save private/session data such as `auth.json`, SQLite chat/log/memory databases, browser/session files, secrets, `.env` files, or live owner-button queue contents.

## Import

On another Windows computer or a fresh Codex setup:

```powershell
git clone https://github.com/zdhconsulting/codex-ai-systems.git C:\Repos\codex-ai-systems
cd C:\Repos\codex-ai-systems
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
C:\Users\zev\.codex\scripts\codex-doctor.cmd
```

From an already-cloned repo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Install selected packs instead of everything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ListPacks
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Pack Founder,Builder,Designer
```

Open the new-user Skill Catalog:

```powershell
& ".\catalog\Start Skill Catalog.bat"
```

## Skill Packs

- `Core`: owner buttons, Next protocol, ChatGPT usage routing, gear routing, git guard, handoffs, project freshness, and health checks.
- `ChatGPT`: routes writing, brainstorming, strategy, summaries, learning, and second opinions to ChatGPT when Codex tools are not needed.
- `Founder`: founder/operator writing, meetings, handoffs, owner-button extraction, lead/domain/support/file workflows.
- `Builder`: implementation, CI/debugging, deploy prep, migrations, logs, PR review, and changelog workflows.
- `Designer`: visual deliverables, frontend polish, brand consistency, screenshot QA, image cleanup, and face-preservation rules.
- `Knowledge`: Notion-ready research, meetings, specs, decisions, and implementation planning.
- `Revenue`: ads, leads, invoices, support, spreadsheets, giveaways, resumes, and media downloads.
- `XHigh`: self-bounce, CEO/CTO/Programmer/QA council mode, and risky-work guardrails.

## Common Commands

Run the local systems health check:

```powershell
.\scripts\codex-doctor.cmd
.\scripts\codex-doctor.cmd -Smoke
```

Route non-code work to ChatGPT to preserve Codex usage:

```powershell
.\scripts\chatgpt-route.cmd "draft a client email from these notes"
.\scripts\chatgpt-route.cmd "brainstorm poster concepts for this launch"
.\scripts\chatgpt-return.cmd -Print
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

Refresh project freshness colors:

```powershell
.\scripts\codex-project-freshness.cmd
```

If Desktop did not show the left-bar project marker colors after restart, run this and then close Codex Desktop:

```powershell
.\scripts\codex-project-freshness-after-exit.cmd
```

Force a specific model/profile route:

```powershell
.\scripts\codex-low.cmd "fix typo in README"
.\scripts\codex-medium.cmd "add dashboard panel"
.\scripts\codex-high.cmd "debug failing tests"
.\scripts\codex-xhigh.cmd "change auth permissions"
.\scripts\codex-xhigh-bounce.cmd "change auth permissions"
.\scripts\codex-xhigh-raw.cmd "change auth permissions"
.\scripts\codex-council.cmd "build billing-safe workflow"
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

Council mode is enforced by default for xhigh implementation launched through `codex-auto.cmd`. It stages the task as CEO Agent requirements, CTO Agent architecture, Programmer Agent implementation, and Tester/QA Agent review/fix loops. The preflight must include `CEO Agent`, `CTO Agent`, `Tester/QA Agent`, and `Programmer Brief`, or implementation does not start. Use `codex-xhigh-raw.cmd` or `[nocouncil]` only when raw xhigh is explicitly needed.

`gpt-5.4-mini` is available but not used by default; keep it as a low/medium fallback if Spark is too shallow or unavailable.

## ChatGPT Usage Routing

Use ChatGPT when the task does not need local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, app connectors, or owner-button queue state.

Route to ChatGPT for brainstorming, naming, ideation, emails, copy, strategy, learning, explanations, critiques, summaries, outlines, meeting notes, rough research synthesis, simple classification, second opinions, and graphic design direction like moodboards, layout concepts, ad/poster/social concepts, image prompt drafting, color palettes, and typography ideas when no local asset editing is needed.

Keep work in Codex for code, repo inspection, local files, tests, builds, commits, pushes, PRs, deployments, CI, logs, screenshots, browser/app verification, durable `.codex` system changes, active goals, owner-button queues, actual asset generation or editing, local design files, web/app UI implementation, screenshot QA, brand-system work, production deliverables, real-person face work requiring exact pixel preservation, and high-risk auth/billing/security/database/permissions/production work.

The ChatGPT route copies a ready prompt to the clipboard and opens ChatGPT. It asks ChatGPT to end with a `CODEX_RETURN_PACKET`. It does not switch the current Codex Desktop chat to a different model.

To bring results back, copy the ChatGPT answer and run:

```powershell
.\scripts\chatgpt-return.cmd -Print
```

Codex can then continue from the returned summary, decisions, artifact, and next action.

## Project Freshness Colors

`install.ps1` configures `~/.codex/config.toml` so `notify` runs `scripts/codex-notify-router.cmd` at turn end. The router forwards the normal computer-use notification, then runs `codex-project-freshness.cmd`.

The freshness script reads saved project roots, checks the most recent file timestamp while skipping common generated folders, and updates Codex Desktop `project-appearances` in `.codex-global-state.json` with visible project marker colors:

- `FRESH`: touched within 24 hours.
- `WARM`: touched within 3 days.
- `AGING`: touched within 7 days.
- `STALE`: touched within 14 days.
- `DORMANT`: untouched longer than 14 days.

CLI output uses ANSI colors. The Codex left bar uses colored project marker/folder icons, not full-row background paint.

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

## GitHub Remote Setup

If this repo is only local, create a GitHub repo named `codex-ai-systems`, then run:

```powershell
git remote add origin https://github.com/zdhconsulting/codex-ai-systems.git
git push -u origin main
```

After that, Codex can run `C:\Users\zev\.codex\scripts\save-codex-systems.cmd` after workflow changes to auto-save them to GitHub.
