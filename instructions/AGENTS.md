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

## ChatGPT Usage Routing

To save Codex usage, route work away from Codex when it does not need local repo access, terminal commands, filesystem edits, tests, git, deployment/debugging, browser verification, app connectors, or owner-button queue state.

Use the ChatGPT route for:

- Brainstorming, naming, ideation, and option generation.
- Emails, messages, posts, copy, tone rewrites, and internal/customer-facing writing.
- Strategy, planning, learning, explanations, critiques, and second opinions.
- Summaries, outlines, meeting notes, rough research synthesis, and simple classification.
- Graphic design direction, moodboards, layout concepts, ad/poster/social concepts, design critique, image prompt drafting, color palettes, and typography ideas when no local asset editing is needed.
- Any task where a ready prompt in ChatGPT is enough and no Codex tool execution is needed.

Keep the work in Codex for:

- Code, repo inspection, local files, tests, builds, commits, pushes, PRs, deployments, CI, logs, screenshots, and browser/app verification.
- Anything needing current workspace context, durable changes under `C:\Users\zev\.codex`, or system backup to GitHub.
- Actual local asset generation or editing, local design files, web/app UI implementation, screenshot QA, brand-system work, production deliverables, or real-person face work requiring exact pixel preservation, unless Zev explicitly asks ChatGPT to be the image surface; then use ChatGPT auto-orchestration.
- Auth, security, billing, database, permissions, production risk, and ambiguous failures. Use xhigh/council; ChatGPT can give a second opinion, but Codex should execute only after guardrails.

When a task should leave Codex, say `ChatGPT route recommended - brief reason`, then use:

`C:\Users\zev\.codex\scripts\chatgpt-route.cmd "TASK"`

Default to full automation when Chrome/ChatGPT web is available: use the Chrome browser plugin to open or claim ChatGPT, submit the routed prompt, wait for completion, copy/import text results, or download generated image assets. Do not ask Zev to paste/copy unless the browser automation bridge is unavailable or ChatGPT itself requires login, CAPTCHA, payment, account verification, safety confirmation, or another true owner-only action.

For ChatGPT image generation, Codex is the orchestrator: prepare an IP-safe prompt, submit it through ChatGPT web, wait for the image, download the generated asset, save it to the project assets folder when one is obvious or `C:\Users\zev\OneDrive\Documents\ZDH Generated Assets`, visually inspect it, and return the local file link plus image preview. Avoid exact copyrighted characters, logos, brand trade dress, and real-person face reinterpretation unless the user supplies allowed source material and exact preservation is possible.

Manual fallback: this copies a ChatGPT-ready prompt to the clipboard, opens ChatGPT, and asks ChatGPT to end with a `CODEX_RETURN_PACKET`. Do not claim the current Desktop chat has switched models. The current Codex session is only dispatching; ChatGPT does the routed work.

To bring manual ChatGPT results back into Codex, Zev copies the ChatGPT answer, says `import ChatGPT result`, then Codex reads the clipboard with:

`C:\Users\zev\.codex\scripts\chatgpt-return.cmd -Print`

After import, continue from the returned summary, decisions, artifact, and Codex next action.

## Future Project Rule Seeding

The global `C:\Users\zev\.codex\AGENTS.md` is the default memory for new Codex sessions. To make any project carry the same rules explicitly, run this from the project root:

`C:\Users\zev\.codex\scripts\codex-project-rules.cmd`

This creates or updates a marked Zev workflow block in that project's `AGENTS.md` while preserving existing project-specific rules.

Check the selected route without launching work:

`C:\Users\zev\.codex\scripts\codex-gear.cmd "TASK"`

Verify the whole gear setup:

`C:\Users\zev\.codex\scripts\codex-gear-test.cmd`

Show current repo, owner buttons, gear routes, and systems backup state:

`C:\Users\zev\.codex\scripts\codex-systems-status.cmd`

Run the full local Codex systems health check:

`C:\Users\zev\.codex\scripts\codex-doctor.cmd`

Refresh project freshness colors in the Codex left bar:

`C:\Users\zev\.codex\scripts\codex-project-freshness.cmd`

If Desktop did not show the left-bar project marker colors after a restart, start the after-exit helper, then close Codex Desktop. The helper waits until Desktop is fully closed, rewrites the freshness state with UTF-8 without BOM, and relaunches Codex:

`C:\Users\zev\.codex\scripts\codex-project-freshness-after-exit.cmd`

Force a specific route:

- `C:\Users\zev\.codex\scripts\codex-low.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-medium.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-high.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh-bounce.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-xhigh-raw.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-bounce.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-council.cmd "TASK"`
- `C:\Users\zev\.codex\scripts\codex-review.cmd "TASK"`

The actual model/profile plan is:

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
