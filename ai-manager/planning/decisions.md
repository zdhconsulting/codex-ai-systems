# Decisions

## 2026-06-14

- AI Manager belongs in `zdhconsulting/codex-ai-systems`, not in the temporary `New project 2` workspace.
- AI Manager is a conductor worker and project manager for Zev's projects.
- First slice is a local manager report before a UI or scheduled daemon.
- Repair behavior must be bounded: report by default, run only explicit configured fix commands with a fix flag, and keep existing owner/commander approval gates.
