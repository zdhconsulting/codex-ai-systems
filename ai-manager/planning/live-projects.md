# Live Project Interaction Map

Last reviewed: 2026-06-14

AI Manager's job is to understand Zev's live project system, not just individual repos. It should know where each project lives, what "running" means, which specialist owns the next move, and when Codex must stop for an owner or commander gate.

## Source Order

1. `ai-manager/projects.live.json` for the manager's runnable project registry.
2. `C:\Repos\Mr.SEO\data\sites.json` for the active full-time SEO site roster.
3. Each repo's `AGENTS.md`, `planning/STATE.md`, and `README.md` for local rules.
4. `C:\Users\zev\.codex\queues\owner-buttons.json` for external-account blockers.
5. `C:\Users\zev\OneDrive\Documents\New project 2\pinned_projects.json` for dashboard/Bossman pinned projects.

## Global Interaction Rules

- Inspect and report freely.
- Before commits, pushes, branch changes, PRs, deployments, or destructive git actions, run `C:\Users\zev\.codex\scripts\git-guard.cmd`.
- Use `Owner button needed` only for account logins, private inboxes, secrets, billing, security/account prompts, CAPTCHA, microphone/browser permissions, deployment buttons that require Zev's session, and similar external actions.
- Use `Commander approval needed` for strategy, cost, production state, permissions, repo history, destructive cleanup, or ambiguous risky moves.
- Do not invent facts for medical, pricing, proof, credentials, reviews, client examples, legal/privacy/security, or publishable authority claims.
- Prefer repo-contained fixes, local tests, live URL checks, and clear handoffs.
- Treat dirty worktrees as attention items, not automatic cleanup targets.

## Control Plane Projects

| Project | Home | How AI Manager Should Interact |
| --- | --- | --- |
| AI Manager | `C:\Repos\codex-ai-systems\ai-manager` | Own the registry, health report, interaction map, and safe repair policy. |
| Codex AI Systems | `C:\Repos\codex-ai-systems` | Source of truth for Zev's Codex workflows, skills, scripts, profiles, and backup/install path. Run `save-codex-systems.cmd` after user-level `.codex` changes. |
| Bossman | `C:\Repos\bossman` plus local source references in `New project 2` | Nudge/dispatch layer for pinned projects. It can queue Codex follow-ups, but does not bypass owner/commander gates. |
| ZDH Live Project Manager | `C:\Users\zev\OneDrive\Documents\New project 2` | Desktop dashboard, LiveKit voice experiments, Sponder site, planning scaffold, and local dashboard utilities. Current tree has many untracked files; review before any push or cleanup. |
| Mr.SEO | `C:\Repos\Mr.SEO` | Search/AI-answer visibility system. Use it for active SEO roster, focus site, daily actions, writer queues, ranking intake, and owner facts. |
| MrReviewer | `C:\Repos\MrReviewer` | Audit/scoring system. Use it to crawl sites, run responsive proof, score forms/trust/search readiness, and generate Bossman packets. |
| ZDH AI Dashboard | `C:\Repos\ZDH-AI-Dashboard` | Web/desktop dashboard for local project state and Bossman visibility. Use npm scripts for dev/build/desktop packaging. |

## Active Full-Time SEO Sites

These come from `C:\Repos\Mr.SEO\data\sites.json` and are the main live portfolio.

| Site | Repo | Live URL | Interaction Notes |
| --- | --- | --- | --- |
| Botox Tel Aviv / THEA | `C:\Repos\Botox-Israel` | `https://www.botoxtelaviv.com/` | Medical/beauty local SEO. Do not invent treatment, provider, safety, credential, proof, or pricing facts. GA4/GTM and owner facts are gated. |
| English Comedy TLV | `C:\Repos\EnglishComedyTLV` | `https://englishcomedytelaviv.com/` | Event/discovery site. Preserve event, ticket, venue, schema, and form accuracy. Several worktrees exist; choose task-specific worktree deliberately. |
| ExplainMyBusiness | `C:\Repos\explainmybusiness` | `https://explainmybusiness.com/` | Static explainer-video lead site. DNS, Vercel domain/deploy buttons, reputation-review submissions, and inbox proof are owner-only. |
| Israel Digital Army | `C:\Repos\IsraelDIgitalArmy.com` | `https://israeldigitalarmy.com/` | Advocacy/entity site. Be factual and reputation-aware; public positioning changes need care. |
| IsraelOffshore | `C:\Users\zev\OneDrive\Documents\IsraelOffshore` | `https://israeloffshore.com/` | Current Mr.SEO focus site. Codex can patch on-page clarity; form activation and proof/client facts are owner-gated. |
| Web Design Israel | `C:\Repos\webdesignisrael` | `https://webdesignisrael.com/` | Canonical repo is `webdesignisrael.com`; archive folder is read-only history. Run generated-page build before deploy checks. |
| ZDH Consulting | `C:\Repos\zdhconsultingsite` | `https://zdhconsulting.com/` | Main agency site. GA4, Search Console, FormSubmit inbox proof, and production account controls are owner-only. |
| ZDH Sales | `C:\Repos\zdhsales` | `https://www.zdhsales.com/` | Static sales site. Keep FormSubmit token flow intact; inbox activation is owner-only. |
| Zev Hecht | `C:\Users\zev\OneDrive\Documents\zevhecht.com` | `https://zevhecht.com/` | Personal/entity site. Use the Documents repo, not the Desktop folders that resolve to `C:\Users\zev`. Vercel promotion is owner-only. |

## Other Live Or Parked Projects

| Project | Home | Running Signal | Interaction Notes |
| --- | --- | --- | --- |
| Icecreamfinder | `C:\Repos\Icecreamfinder` | `https://icecreamfinder.vercel.app/` | Maps/Places app with optional Supabase review moderation. Env vars, Supabase setup, and Vercel deploy dashboard are owner-only. |
| Sponder Standup | `New project 2` | `https://sponderstandup.com/` | Public site is live, but Mr.SEO marks it skipped by owner. Do not generate active SEO/ranking/writer work until re-enabled. |
| ContactFormBlaster | `C:\Repos\contactformblaster` | `https://zdhconsulting.github.io/contactformblaster/` | Authorized form QA tool only. Dry-run by default; real submission requires explicit authorization. Current public Pages URL returns 404. |
| FormBlaster | `C:\Repos\formblaster` | local/repo health | Local/desktop form automation project. Keep authorization and anti-abuse constraints central. |
| Yishai Fleisher Build Israel | `C:\Repos\yishai-fleisher-buildisrael` | `https://buildisrael.com/` | Static redesign repo; no origin currently. GitHub repo creation/push is blocked on owner GitHub auth. |
| Book Production | `C:\Repos\book` | local/repo health | Creative/book project, not a live service. Avoid cleanup of drafts/assets unless explicitly asked. |

## Current Live URL Sweep

Checked on 2026-06-14.

- 200: `botoxtelaviv.com`, `englishcomedytelaviv.com`, `explainmybusiness.com`, `israeldigitalarmy.com`, `israeloffshore.com`, `webdesignisrael.com`, `zdhconsulting.com`, `zdhsales.com`, `zevhecht.com`, `sponderstandup.com`, `icecreamfinder.vercel.app`, `mr-seo.vercel.app`, `bossmanai.vercel.app`.
- 404: `mr-reviewer.vercel.app`, `zdhconsulting.github.io/contactformblaster/`.

## Worktree Notes

- `C:\Repos\webdesignisrael` is canonical. `C:\Repos\webdesignisrael-wrong-remote-archive-20260614` is archive/history.
- `C:\Repos\EnglishComedyTLV-*` folders are task-specific worktrees/hotfix clones. Do not edit one accidentally just because it has a cleaner branch.
- Desktop folders under `C:\Users\zev\OneDrive\Desktop\English Comedy TLV`, `Israel Botox`, and `zevhecht.com` resolve to a broad `C:\Users\zev` git root and should not be treated as canonical project repos.

## Manager Behavior

AI Manager should produce three levels of answer:

1. `running`: expected path, repo, required files, and health URLs are OK, with no owner-specific blockers.
2. `needs-attention`: project is basically reachable, but has dirty files, owner buttons, skipped check commands, stale runner warnings, or deployment/account uncertainty.
3. `not-running`: path missing, repo wrong, required files missing, expected process stopped, health URL down, or check command failed.

When not running, AI Manager should say why, identify the likely owner of the next move, and either make a safe repo-contained fix or record the exact owner/commander gate.
