# Personal Codex Workflow

Use `$owner-button-workflow` for Zev's projects.

Codex should drive implementation work fast: code, tests, debugging, verification, commits, pushes, deployment prep, and clear explanations.

Zev should only be pulled in for real-world owner-only tasks: account logins, env vars or secrets from private accounts, billing/security prompts, account verification, deploy buttons that require Zev's session, and explicit approvals.

Use `Owner button needed` only when truly blocked by an external account or user-only action. Include the exact site/tool, exact action, why Codex cannot do it, and what Codex will do next.

Use `Commander approval needed` only when Zev needs to approve a next step that affects strategy, cost, risk, production state, permissions, or repo history.

When Zev reports an owner-only task is complete, say exactly:

`GATE BROKEN. Owner button pressed. We're through.`

Then immediately continue working.

## Next Protocol

When Zev says `Next`, treat it as an instruction to continue the current mission with the best next action. Do not ask what `Next` means, and do not turn it into a menu of options unless a real approval decision is required.

Interpret `Next` by this priority order:

1. Continue the active goal's next unfinished success criterion.
2. Clear any concrete blocker that Codex can clear without Zev.
3. Verify the work that was just done with tests, builds, smoke checks, screenshots, logs, or repo state as appropriate.
4. Save durable progress: commit, push, create/update handoff notes, sync reusable systems, or document the changed workflow.
5. Make the result portable to another Codex or computer.
6. Clean up generated clutter only after classifying it and avoiding loss of useful work.
7. Improve automation so Zev has to press fewer buttons next time.
8. If no active goal exists, infer the most useful continuation from recent context, owner-button queue, git status, and handoff state.

For visible execution, start substantial `Next` turns with:

`Next = SPECIFIC_ACTION. Gear: low|medium|high|xhigh - brief reason.`

Then execute. Stop only for `Owner button needed`, `Commander approval needed`, or a genuine lack of recoverable context after checking local state.

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

## Actual Gear Routing

When launching new Codex CLI/automation work, use the real profile router:

`C:\Users\zev\.codex\scripts\codex-auto.cmd "TASK"`

Check the selected route without launching work:

`C:\Users\zev\.codex\scripts\codex-gear.cmd "TASK"`

Force a specific route:

- `C:\Users\zev\.codex\scripts\codex-low.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-medium.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-high.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-review.cmd "TASK"`

The actual model/profile plan is:

- `low` / `fast`: `gpt-5.3-codex-spark`, low reasoning, for ultra-fast simple coding and mechanical tasks.
- `medium` / `balanced`: `gpt-5.4`, medium reasoning, for normal implementation work.
- `high` / `deep`: `gpt-5.5`, high reasoning, for debugging, CI, regressions, multi-file work, deploy issues, and verification-heavy tasks.
- `xhigh` / `max`: `gpt-5.5`, xhigh reasoning, for architecture, auth, security, billing, database, permissions, and production-risk work.
- `review`: `codex-auto-review`, medium reasoning, for explicit code review, PR review, diff review, or commit review.

Available but not the default:

- `gpt-5.4-mini`: keep as a future low/medium fallback if `gpt-5.3-codex-spark` is too shallow or unavailable.

In an already-open Desktop chat, Codex cannot guarantee changing the current session's model just by printing a gear label. The label still controls working behavior. Actual model switching happens when the task is launched through `codex-auto.cmd` or a Codex profile.

## Reasoning Gear Examples

If a task includes multiple risk levels, choose the highest gear needed for the riskiest part. Move down again once the risky part is finished.

Use `low` for quick, obvious work:

- Fix typos, labels, headings, button text, or README wording.
- Add or update a simple link when the target is already known.
- Change one color, spacing value, icon, or small CSS rule.
- Run status commands like `git status`, `owner-button.cmd list`, or `git-guard.cmd`.
- Add a single static config value when the source and destination are clear.
- Rename a local variable or update a small obvious import.
- Re-run a known build command after a tiny change.
- Copy a known file into the right folder.
- Check whether a file, branch, or remote exists.
- Answer a narrow question from visible local context.

Use `medium` for normal build work:

- Add a small page, component, form, dashboard panel, or route.
- Implement a straightforward feature with tests.
- Fix an ordinary bug when the cause is local and easy to reproduce.
- Wire an API response into UI when the contract is already known.
- Add validation, loading states, empty states, or simple error handling.
- Update project docs after a feature change.
- Make routine responsive layout improvements.
- Add a script or CLI helper that follows an existing pattern.
- Integrate a known library in a small, low-risk way.
- Prepare a normal commit after verifying the repo with `git-guard.cmd`.

Use `high` when diagnosis or blast radius matters:

- Debug failing tests, failing CI, broken builds, or runtime crashes.
- Investigate regressions after a change.
- Review code for bugs, missing tests, or behavioral risk.
- Touch several files or shared helpers where side effects are possible.
- Fix deployment problems, build packaging, or app launch behavior.
- Optimize performance when measurement or tradeoffs are involved.
- Resolve merge conflicts or dirty worktree complications.
- Debug GitHub Actions logs or failing checks.
- Change data flow, caching, routing, or state management.
- Verify a fix across desktop/mobile/browser/app surfaces.

Use `xhigh` for high-stakes or ambiguous decisions:

- Architecture changes, major refactors, or framework migration.
- Auth, permissions, roles, sessions, OAuth, SSO, or account linking.
- Billing, payments, subscriptions, invoices, or paid-plan limits.
- Security-sensitive code, secrets, tokens, webhooks, or private data.
- Database migrations, schema changes, destructive data operations, or backups.
- Production deploys with user impact, downtime, or rollback risk.
- DNS, domain ownership, email authentication, or SSL/certificate changes.
- Legal/compliance/privacy implications.
- Cross-account access decisions or new third-party permissions.
- Ambiguous complex failures where the wrong fix could make things worse.

## Design Work Rules

Use `low` for tiny visual tweaks, `medium` for normal page/component polish, `high` for multi-screen UX/accessibility/responsive verification, and `xhigh` for brand systems, design architecture, checkout/signup/auth, revenue, trust, or production-risk design.

For design or image-editing tasks involving a real person's face, do not redraw, regenerate, stylize, beautify, smooth, age, or reinterpret the face. Preserve the original face pixels exactly by masking, cutting, copying, and pasting the source face into the final composition. If the source face is unavailable, or the requested edit would require generating a new face, ask for the needed source image or explain that exact preservation is not possible. Backgrounds, layout, clothing, framing, and surrounding design can change; the face itself stays untouched unless Zev explicitly asks to edit the face.

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

## Codex Systems Auto-Save

After changing user-level Codex workflow files under `C:\Users\zev\.codex` such as `AGENTS.md`, scripts, reasoning profiles, queues, or personal skills, run:

`C:\Users\zev\.codex\scripts\save-codex-systems.cmd`

This syncs the live setup into `C:\Repos\codex-ai-systems`, commits changes, and pushes to `https://github.com/zdhconsulting/codex-ai-systems.git` once the remote exists.
