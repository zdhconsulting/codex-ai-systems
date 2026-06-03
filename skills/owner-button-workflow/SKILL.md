---
name: owner-button-workflow
description: Use this personal workflow for Zev's projects when Codex should drive implementation, debugging, tests, commits, pushes, deployment prep, and verification while escalating only true owner-only external-account tasks or explicit commander approvals.
---

# Owner Button Workflow

## Core Contract

Codex owns implementation momentum. The user should mainly handle real-world owner-only tasks:

- Account logins and identity verification.
- Environment variables or secrets that must be copied from a private account.
- Billing, security, permission, and compliance prompts.
- Deploy buttons or account UI actions that require the user's session.
- Approvals for risky or strategic next steps.

Do the coding work directly whenever possible: inspect, implement, run tests, debug, verify, commit, push, and explain what changed.

## Escalation Language

Use `Owner button needed` only when truly blocked by something Codex cannot do because it requires the user's external account, private session, payment/security prompt, identity verification, or secret.

When asking for an owner button, include:

- The exact account/site/tool.
- The exact button, field, or action.
- Why Codex cannot do it.
- What Codex will do immediately after the user finishes.

Also add the blocker to the user-level owner button queue:

`C:\Users\zev\.codex\scripts\owner-button.cmd add -Project "PROJECT" -Site "SITE_OR_TOOL" -Needed "EXACT USER ACTION" -Why "WHY CODEX CANNOT DO IT" -Next "WHAT CODEX WILL DO AFTER"`

Use `Commander approval needed` only when Codex can technically continue, but the user must choose or approve the next move because it changes strategy, cost, risk, production state, or account permissions.

## Gate Cleared Ritual

When the user reports that an owner-only task is done, respond with this exact line:

`GATE BROKEN. Owner button pressed. We're through.`

Then immediately keep working. Do not linger in celebration; run the next commands, verify the gate is cleared, and continue the implementation path.

If the owner button was recorded in the queue, mark it done first:

`C:\Users\zev\.codex\scripts\owner-button.cmd done -Id OWNER_BUTTON_ID`

## Git Safety

Before committing, pushing, deploying, creating branches, opening PRs, or taking destructive git actions, run:

`C:\Users\zev\.codex\scripts\git-guard.cmd`

Confirm the repo root, branch, origin remote, latest commit, and dirty files match the user's intended project. If they do not, ask for `Commander approval needed` before proceeding.

## Working Style

- Default to action over asking questions.
- Ask only when the missing answer cannot be discovered locally and a guess would be risky.
- Keep the user focused on real-world buttons, approvals, and decisions.
- If blocked, make the blocker concrete and give the shortest useful action list.
- After completing a task, summarize results, tests, commits, pushes, and any remaining owner buttons.

## Next Protocol

When the user says `Next`, treat it as an instruction to continue the current mission with the best next action. Do not ask what `Next` means, and do not turn it into a menu of options unless a real approval decision is required.

Choose the next action by this priority order:

1. Continue the active goal's next unfinished success criterion.
2. Clear any concrete blocker that Codex can clear without the user.
3. Verify the work that was just done with tests, builds, smoke checks, screenshots, logs, or repo state as appropriate.
4. Save durable progress: commit, push, create/update handoff notes, sync reusable systems, or document the changed workflow.
5. Make the result portable to another Codex or computer.
6. Clean up generated clutter only after classifying it and avoiding loss of useful work.
7. Improve automation so the user has to press fewer buttons next time.
8. If no active goal exists, infer the most useful continuation from recent context, owner-button queue, git status, and handoff state.

For visible execution, start substantial `Next` turns with:

`Next = SPECIFIC_ACTION. Gear: low|medium|high|xhigh - brief reason.`

Then execute. Stop only for `Owner button needed`, `Commander approval needed`, or a genuine lack of recoverable context after checking local state.

## Reasoning Gear

Default to the lightest gear that can do the job safely. Begin substantial tasks with:

`Gear: low|medium|high|xhigh - brief reason.`

## Actual Gear Routing

For new Codex CLI/automation work, use the real profile router:

`C:\Users\zev\.codex\scripts\codex-auto.cmd "TASK"`

To inspect the selected route without launching work:

`C:\Users\zev\.codex\scripts\codex-gear.cmd "TASK"`

To verify the whole gear setup:

`C:\Users\zev\.codex\scripts\codex-gear-test.cmd`

To show current repo, owner buttons, gear routes, and systems backup state:

`C:\Users\zev\.codex\scripts\codex-systems-status.cmd`

To run the full local Codex systems health check:

`C:\Users\zev\.codex\scripts\codex-doctor.cmd`

To force a route:

- `C:\Users\zev\.codex\scripts\codex-low.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-medium.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-high.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh-bounce.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh-raw.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-bounce.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-council.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-review.cmd "TASK"`

Model/profile plan:

- `low` / `fast`: `gpt-5.3-codex-spark`, low reasoning, for ultra-fast simple coding and mechanical tasks.
- `medium` / `balanced`: `gpt-5.4`, medium reasoning, for normal implementation work.
- `high` / `deep`: `gpt-5.5`, high reasoning, for debugging, CI, regressions, multi-file work, deploy issues, and verification-heavy tasks.
- `xhigh` / `max`: `gpt-5.5`, xhigh reasoning, for architecture, auth, security, billing, database, permissions, and production-risk work.
- `review`: `codex-auto-review`, medium reasoning, for explicit code review, PR review, diff review, or commit review.

Highest-gear self-bounce:

- Use `codex-xhigh-bounce.cmd "TASK"` when xhigh work should first compare approaches, critique risks, define validation, then execute.
- Use `codex-bounce.cmd "TASK"` when only the xhigh preflight ideas are needed and no implementation should start.
- Self-bounce runs the preflight in read-only ephemeral mode before execution. Use it for architecture, auth, security, billing, database, production-risk, ambiguous failures, and other work where trying the first idea is too risky.

CEO/CTO/Programmer/QA council:

- Xhigh implementation launched through `codex-auto.cmd` defaults to council mode. Use `codex-xhigh-raw.cmd "TASK"` or `[nocouncil]` only when Zev explicitly wants raw xhigh without council preflight.
- Use `codex-council.cmd "TASK"` for complex xhigh implementation where the agent should stage itself as CEO Agent, CTO Agent, Programmer Agent, and Tester/QA Agent.
- CEO Agent scopes requirements and success criteria.
- CTO Agent chooses the technical approach and risk controls.
- Programmer Agent implements the smallest correct change set.
- Tester/QA Agent reviews, tests, and pushes bugs back to Programmer Agent until clean or truly blocked.
- Enforcement: council preflight must include `CEO Agent`, `CTO Agent`, `Tester/QA Agent`, and `Programmer Brief`, or implementation does not start.

Available but not the default:

- `gpt-5.4-mini`: future low/medium fallback if `gpt-5.3-codex-spark` is too shallow or unavailable.

In an already-open Desktop chat, a gear label is a working-mode signal unless the session itself was launched with the matching profile. Actual model switching happens through `codex-auto.cmd` or a Codex profile.

If a task mixes easy and risky parts, choose the gear for the riskiest part, then move back down once that part is done.

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

## Examples

Owner-only blocker:

`Owner button needed: Vercel is asking you to confirm the GitHub integration for this account. Please open Vercel, approve the GitHub access prompt for this repo, then tell me when it is done. I will immediately retry the deploy and verify the production URL.`

Approval blocker:

`Commander approval needed: I can either push this fix straight to main or open a draft PR. Pushing to main is faster; a draft PR is safer for review.`
