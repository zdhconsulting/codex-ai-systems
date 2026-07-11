# Codex Plugin for Claude Code - Zev Telemetry Patch

This is a fail-closed compatibility patch for the official OpenAI `codex@openai-codex` Claude Code plugin version 1.0.6.

## Why It Exists

The official plugin works, but version 1.0.6 does not include elapsed time and Codex token usage in every stored result. Its native `review/start` path also records zero tokens on this machine even though the review succeeds.

The patched command surface keeps the official plugin and adds:

- Exact elapsed time on completed, failed, and cancelled jobs.
- Exact Codex app-server token totals and available input/output/cache/reasoning breakdowns.
- A read-only structured `/codex:review` path that reports exact usage and deletes its temporary Codex thread after capturing the result.
- A read-only state-database fallback for persisted task threads when the app server omits its token notification.
- A transfer-receipt fallback for Codex 0.144.1, which moved Claude import receipts from the old JSON ledger into `state_5.sqlite`.
- `RUN_USAGE` appended to human-readable results plus structured `runMetrics` in job JSON.

No token estimates are used. Missing authoritative telemetry is reported as `unavailable`.

## Verification

On 2026-07-12, the pilot review found an intentional admin authorization bypass and returned:

`RUN_USAGE elapsed=48.363s tokens=27353 input=25902 cached_input=0 output=1451 reasoning_output=1099 source=codex_app_server`

The pilot repository was restored to a clean, safe state after the test.

The `/codex:transfer` pilot also imported a Claude JSONL transcript and returned a valid Codex resume thread after the SQLite receipt compatibility fix.

## Reapply or Check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zev\.codex\scripts\ensure-codex-plugin-cc.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zev\.codex\scripts\ensure-codex-plugin-cc.ps1
```

The script only applies to verified plugin version 1.0.6. It refuses a newer version or unexpected file contents so an upstream update cannot be silently overwritten with incompatible code.

## Operational Limits

- The stop-time review gate remains disabled.
- Background jobs need a live Claude session or shared runtime. One-shot `claude -p` background launches are not durable supervision by themselves.
- After an official plugin upgrade, port and re-run the pilot before changing the required version.
