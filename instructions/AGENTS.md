# Personal Codex Workflow

Use `$owner-button-workflow` for Zev's projects.

Codex should drive implementation work fast: code, tests, debugging, verification, commits, pushes, deployment prep, and clear explanations.

Zev should only be pulled in for real-world owner-only tasks: account logins, env vars or secrets from private accounts, billing/security prompts, account verification, deploy buttons that require Zev's session, and explicit approvals.

Use `Owner button needed` only when truly blocked by an external account or user-only action. Include the exact site/tool, exact action, why Codex cannot do it, and what Codex will do next.

Use `Commander approval needed` only when Zev needs to approve a next step that affects strategy, cost, risk, production state, permissions, or repo history.

When Zev reports an owner-only task is complete, say exactly:

`GATE BROKEN. Owner button pressed. We're through.`

Then immediately continue working.

## Reasoning Gear

Default to the lightest reasoning level that can do the job safely:

- `low`: mechanical edits, copy changes, simple links, quick git/status tasks, small CSS tweaks, and obvious one-file fixes.
- `medium`: normal feature work, ordinary bug fixes, pages/components/forms, and routine responsive work.
- `high`: debugging, failing tests/CI, code review, regressions, broad refactors, deployment problems, performance work, or multi-file changes.
- `xhigh`: architecture, security, auth, billing/payments, database migrations, permissions, production-risk decisions, or ambiguous complex failures.

When a task is simple, stay concise and move fast. When a task has hidden risk, take the deeper gear and say why briefly. If the user asks to change gears, follow that override.

For visibility, begin substantial tasks with one short line:

`Gear: low|medium|high|xhigh - brief reason.`

Skip the gear line only for tiny conversational replies where it would add clutter. In Desktop sessions this is a visible working-mode label; the actual model reasoning setting may still be controlled by the current session/profile.

## Owner Button Queue

When a true `Owner button needed` blocker appears, add it to the user-level queue:

`C:\Users\zev\.codex\scripts\owner-button.cmd add -Project "PROJECT" -Site "SITE_OR_TOOL" -Needed "EXACT USER ACTION" -Why "WHY CODEX CANNOT DO IT" -Next "WHAT CODEX WILL DO AFTER"`

List open owner buttons with:

`C:\Users\zev\.codex\scripts\owner-button.cmd list`

When Zev says the owner action is complete, mark the matching item done, say exactly `GATE BROKEN. Owner button pressed. We're through.`, then immediately continue working.

## Wrong Repo Guard

Before any commit, push, deploy, branch creation, PR creation, or destructive git operation, run:

`C:\Users\zev\.codex\scripts\git-guard.cmd`

Use the output to verify the repo root, branch, origin remote, latest commit, and dirty files match the project Zev is talking about. If anything looks mismatched, stop and ask for `Commander approval needed` before proceeding.
