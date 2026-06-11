# Routing Taxonomy

## Send To ChatGPT

- Writing: email drafts, rewrites, tone changes, sales copy, posts, headlines, taglines.
- Ideation: names, domains, angles, campaigns, offers, options, pros/cons.
- Strategy: non-production planning, positioning, critiques, second opinions.
- Synthesis: summaries, outlines, meeting notes, simple classification, research synthesis.
- Learning: explanations, teaching, conceptual comparisons.
- Design direction: moodboards, layout concepts, palettes, typography, image prompts, critique.
- ChatGPT-native creative generation: fictional/sample logos, generated image sheets, ad creative drafts, poster concepts, and visual mockups when no local repo editing, exact brand asset preservation, or real-person face preservation is needed.
- Translation/transformation: translate, condense, expand, turn rough notes into polished text.

## Keep In Codex

- Local repo or filesystem context.
- Code edits, debugging, tests, builds, linting, git, commits, pushes, PRs, CI.
- Deployment, logs, browser/app verification, screenshots, localhost.
- Connected apps or private state: Gmail, Slack, Notion, Linear, Jira, GitHub, Vercel, Supabase, Stripe, Datadog, Sentry, analytics, Search Console, Cloudflare.
- Owner-button queues, active goals, `.codex` systems, skills, scripts, automations.
- Secrets, tokens, auth, billing, payments, database, permissions, security, production risk.
- Real-person face asset work requiring exact pixel preservation.

## Edge Cases

- "Summarize this pasted text" can go to ChatGPT.
- "Summarize `src/app.ts`" stays in Codex because it needs local files.
- "Draft a reply to this pasted email" can go to ChatGPT.
- "Find urgent Gmail replies" stays in Codex because it needs a connector/private inbox.
- "Research current competitors" can go to ChatGPT if no local repo or account data is required.
- "Apply this copy to the site" stays in Codex.
- "Make up four client logos for a bridge test" goes to ChatGPT because fictional creative generation is detachable.
- "Download the generated ChatGPT logo image into this project folder" stays in Codex because it needs local filesystem work.
- "Create client logos for real ZDH clients" can go to ChatGPT for concepts only after Zev supplies the client facts; do not invent real clients unless Zev explicitly says it is a fictional test.
- Use `chatgpt-auto-route.cmd` when the task should be logged as a ChatGPT bridge session with prompt, response, downloaded assets, and savings events.
