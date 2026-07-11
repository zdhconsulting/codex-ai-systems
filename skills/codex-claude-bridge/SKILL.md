---
name: codex-claude-bridge
description: Send bounded local project work from Codex to Claude Code or Fable and import a typed return receipt without manual copy-paste. Use when Zev asks Codex to send a file or plan to Claude, request a Claude second opinion, continue one controlled Codex-Claude review round, import a Claude result, or troubleshoot the PC-local Claude bridge.
---

# Codex Claude Bridge

Keep Codex as conductor. Use Claude only for one bounded review or critique and require a structured receipt.

## Run A Review

1. Confirm the task is read-only and contains no secrets, account data, or unrelated history.
2. Keep input files inside the project workspace. Pass `-AllowedRoot` explicitly for any external input.
3. Preview without provider use:

   ```powershell
   C:\Users\zev\.codex\scripts\claude-bridge.cmd -PlanOnly -Project "PROJECT" -Task "TASK" -InputFile "FILE" -Model fable
   ```

4. Before the first real invocation, obtain `Commander approval needed` because Claude usage may consume plan or API allowance.
5. After approval, rerun without `-PlanOnly`. Read the normalized `receipt.json` or the packet printed by the command.
6. Let Codex decide whether one revision round is useful. Never exceed the packet's hard round limit.

## Enforce Authority

- Keep v1 read-only. Do not add an edit mode silently.
- Require `--safe-mode`, `--permission-mode plan`, `Read,Glob,Grep` only, empty strict MCP configuration, no Chrome, and no session persistence.
- Never use `--dangerously-skip-permissions`, Bash, Edit, Write, network tools, deployment, Git, outreach, or billing actions.
- Reject malformed, stale, mismatched, duplicate, or write-claiming receipts.
- Treat chat text as notification only. The exchange directory and typed JSON artifacts are the source of truth.

## Diagnose

Run the offline suite without contacting Claude:

```powershell
C:\Users\zev\.codex\scripts\claude-bridge-smoke-test.cmd
```

Read [protocol.md](references/protocol.md) when debugging packet fields, status states, retries, or receipt validation. Read the JSON schemas when changing the contract.
