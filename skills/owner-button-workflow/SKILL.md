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

## Examples

Owner-only blocker:

`Owner button needed: Vercel is asking you to confirm the GitHub integration for this account. Please open Vercel, approve the GitHub access prompt for this repo, then tell me when it is done. I will immediately retry the deploy and verify the production URL.`

Approval blocker:

`Commander approval needed: I can either push this fix straight to main or open a draft PR. Pushing to main is faster; a draft PR is safer for review.`
