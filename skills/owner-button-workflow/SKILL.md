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

## ChatGPT Usage Routing

To preserve Codex usage, route work away from Codex when it does not need local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, app connectors, or owner-button queue state.

Use the ChatGPT route for brainstorming, naming, ideation, emails, copy, strategy, learning, explanations, critiques, summaries, outlines, meeting notes, rough research synthesis, simple classification, second opinions, and graphic design direction such as moodboards, layout concepts, ad/poster/social concepts, image prompt drafting, color palettes, and typography ideas when no local asset editing is needed.

Keep work in Codex for code, repo inspection, local files, tests, builds, commits, pushes, PRs, deployments, CI, logs, screenshots, browser/app verification, durable `.codex` system changes, active goals, owner-button queues, actual local asset generation or editing, local design files, web/app UI implementation, screenshot QA, brand-system work, production deliverables, real-person face work requiring exact pixel preservation, and high-risk auth/billing/security/database/permissions/production work. If Zev explicitly asks ChatGPT to be the image surface, Codex should orchestrate ChatGPT end to end.

When a new task might be detachable, check the gateway first:

`C:\Users\zev\.codex\scripts\codex-gateway.cmd -DryRun "TASK"`

For high-confidence detachable work, dispatch through:

`C:\Users\zev\.codex\scripts\codex-gateway.cmd "TASK"`

When a task should leave Codex manually, say `ChatGPT route recommended - brief reason`, then use:

`C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`

Default to full automation when Chrome/ChatGPT web is available: use the Chrome browser plugin to open or claim ChatGPT, submit the routed prompt, wait for completion, copy/import text results, or download generated image assets. Do not ask Zev to paste/copy unless the browser automation bridge is unavailable or ChatGPT itself requires login, CAPTCHA, payment, account verification, safety confirmation, or another true owner-only action.

For ChatGPT image generation, Codex is the orchestrator: prepare an IP-safe prompt, submit it through ChatGPT web, wait for the image, download the generated asset, save it to the project assets folder when one is obvious or `C:\Users\zev\OneDrive\Documents\ZDH Generated Assets`, visually inspect it, and return the local file link plus image preview. Avoid exact copyrighted characters, logos, brand trade dress, and real-person face reinterpretation unless the user supplies allowed source material and exact preservation is possible.

Manual fallback: do not claim the current Codex Desktop chat has switched models. The current session is only dispatching; ChatGPT does the routed work.

ChatGPT results come back through a `CODEX_RETURN_PACKET`. When Zev copies the ChatGPT result and says `import ChatGPT result`, read it with:

`C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print`

Then continue from the returned summary, decisions, artifact, and Codex next action.

For future projects, seed the project `AGENTS.md` with:

`C:\Users\zev\.codex\scripts\codex-project-rules.cmd`

This preserves existing project-specific rules and updates only the marked Zev workflow block.

If API-based ChatGPT routing is requested, use `Commander approval needed` before adding it because it may require API key setup, billing, model choice, and data-sharing decisions.

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

`codex-gateway.cmd` is the preferred front door for new work because it classifies tasks as `chatgpt`, `codex`, or `hybrid`. It auto-bounces high-confidence detachable work to ChatGPT, keeps local/risky work in Codex, and asks first for mixed work. `codex-auto.cmd` remains the lower-level Codex launcher and includes a simpler AI credits optimizer. Use `$codex-chatgpt-bridge` for routing edge cases, handoff preparation, and `CODEX_RETURN_PACKET` imports.

Gateway savings controls:

- Exact completed ChatGPT packets/assets are cached by project plus normalized task.
- Current/fresh prompts such as latest/current/today/news/price/weather/schedule bypass cache automatically.
- Use `-Refresh` for a new ChatGPT run, `-NoCache` for raw routing tests, and `-SplitHybrid` only when the detachable ChatGPT subtask is clear.
- Use `codex-gateway-tally.cmd` to audit route counts, ChatGPT moves, cache hits, completions, savings estimates, and the reason/signals behind each decision.
- Use `codex-gateway-feedback.cmd` to record route quality after useful or bad runs.

Preview or intentionally dispatch with:

`C:\Users\zev\.codex\scripts\ai-credits-optimizer.cmd -DryRun "TASK"`

Force Codex with `-ForceCodex`, `[codex]`, or `--codex`. Force ChatGPT with `-ForceChatGPT`, `[chatgpt]`, or `--chatgpt`. After ChatGPT returns an answer, import it with:

`C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print -RequirePacket`

To inspect the selected route without launching work:

`C:\Users\zev\.codex\scripts\codex-gear.cmd "TASK"`

To verify the whole gear setup:

`C:\Users\zev\.codex\scripts\codex-gear-test.cmd`

To show current repo, owner buttons, gear routes, and systems backup state:

`C:\Users\zev\.codex\scripts\codex-systems-status.cmd`

To run the full local Codex systems health check:

`C:\Users\zev\.codex\scripts\codex-doctor.cmd`

To refresh project freshness colors in the Codex left bar:

`C:\Users\zev\.codex\scripts\codex-project-freshness.cmd`

If Desktop does not show the project marker colors after a restart, start the after-exit helper and then close Codex Desktop:

`C:\Users\zev\.codex\scripts\codex-project-freshness-after-exit.cmd`

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

Council vs swarm routing:

- Use council mode when one task is high-stakes or strategically risky and needs better internal sequencing before execution: architecture, auth, billing, database, security, permissions, production deploys, ambiguous failures, major refactors, or risky cross-cutting design/system work.
- Use council mode when the problem is mostly one coordinated implementation path, even if it needs CEO/CTO/QA thinking.
- Use swarm mode only when Zev explicitly asks for `swarm`, `agents`, `sub-agents`, `delegate`, `parallel agents`, or equivalent parallel agent work in the current Desktop chat.
- Recommend swarm mode, but do not spawn agents yet, when a task naturally splits into independent lanes that can run in parallel: UX audit + bug audit + performance audit, frontend slice + backend slice with disjoint files, multiple independent codebase investigations, or implementation + independent QA.
- Do not use swarm when the next step is a single blocking diagnosis, when file ownership would overlap heavily, or when coordination overhead is larger than the work.
- When swarm is enabled, Codex remains coordinator: define lanes, assign disjoint write scopes, run local critical-path work, integrate results, verify, and close agents when done.
- If both apply, use council for high-risk strategy/preflight and swarm only for clearly separable implementation, research, or verification lanes after the strategy is clear.

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
