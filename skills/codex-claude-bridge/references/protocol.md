# Codex-Claude Bridge Protocol

## Storage

Each invocation creates an immutable attempt directory under:

`C:\Users\zev\.codex\handoffs\claude\YYYYMMDD-HHMMSS-fff-PROJECT-CORRELATION-ATTEMPT\`

Artifacts:

- `task.json`: normalized authority, objective, file hashes, IDs, and limits.
- `prompt.md`: bounded prompt sent on standard input.
- `command.json`: executable metadata and argument list; never credentials.
- `raw-response.json`: captured stdout, stderr, exit state, and parsed envelope when available.
- `receipt.json`: validated normalized terminal return.
- `status.json`: current terminal or non-terminal state.
- `events.jsonl`: append-only lifecycle events.

## States

- `planned`: packet built; provider was not invoked.
- `invoking`: provider process started.
- `succeeded`: schema-valid receipt accepted.
- `failed`: executable missing, timeout, or non-zero provider exit.
- `quarantined`: provider output exists but violates schema, IDs, attempt, authority, or duplicate rules.

## Retry Rules

- Reuse `correlation_id` across related rounds.
- Create a new `attempt_id` and directory for every invocation.
- Keep `round_number <= max_rounds`; the default maximum is two.
- Never overwrite a terminal receipt.
- Do not continue automatically. Codex decides whether a second round is warranted.

## Authority

Version 1 is read-only. Inputs must resolve beneath `workspace_root` or an explicitly supplied allowed root. The command grants only `Read`, `Glob`, and `Grep` while disabling customizations, MCP access, Chrome integration, session persistence, and write/shell tools.

## Validation

Use [task.schema.json](task.schema.json) and [receipt.schema.json](receipt.schema.json) as the provider-neutral contracts. Runtime receipt schemas additionally pin the run, task, correlation, and attempt IDs with `const` values.
