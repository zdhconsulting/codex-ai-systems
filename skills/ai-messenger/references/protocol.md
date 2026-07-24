# AI Messenger Protocol

## Invariants

1. SQLite is authoritative; browser tabs, chat titles, and process presence are observations only.
2. A message belongs to one channel and names one source and one target endpoint.
3. Both endpoints must be explicitly bound to the channel.
4. The channel workspace must match the target CLI session workspace.
5. A stable idempotency key suppresses duplicate logical sends.
6. A lease prevents concurrent delivery; expired leases retry or dead-letter.
7. The kill switch stops new claims without deleting state.
8. Live delivery is a separate setting and is off by default.
9. Runtime state lives under `%LOCALAPPDATA%`, never OneDrive.
10. Provider process exit is not proof; only a locally validated typed receipt is success.
11. A persistent project session is an identity in the registry, not a resident Claude process.

## Message states

Message state:

`queued -> leased -> awaiting_receipt -> succeeded|blocked|failed`

Dispatch-attempt state:

`intent_written -> process_started -> awaiting_validation -> succeeded`

Failure attempts end as `invalid_receipt`, `retryable_failure`, `dead_letter`, or `orphaned`.

Failures before a receipt return to `queued` until `max_attempts`; the final failure becomes
`dead_letter`. `cancelled` is terminal. Terminal receipts are immutable.

## Required packet identity

Every packet carries:

- `message_id`
- `channel_id`
- `project_id`
- `workspace_root`
- `authority`
- `correlation_id`
- `attempt_id`
- `round_number` and `max_rounds`
- exact source and target endpoint IDs
- bounded payload

Every accepted return must echo message, channel, project, correlation, and attempt IDs; provide a
terminal status, summary, evidence, next action, approval flags, blockers, completed timestamp, and
an empty `files_touched` array for read-only work. The Claude envelope session ID must match the
registered project session.

## Endpoint kinds

- `codex_cli_session`: saved Codex task/session ID plus matching cwd.
- `claude_cli_session`: legacy pre-existing Claude Code session ID plus matching cwd.
- `claude_gateway_session`: gateway-managed named session UUID, matching cwd, registry version, and
  initialized state. First delivery uses `--session-id`; later delivery uses `--resume`.
- `claude_desktop_session`: observation only until an adapter exposes a listener.
- `chrome_conversation`: exact ChatGPT or DeepSeek conversation URL.

## Browser transport

Browser delivery is delegated to one Codex browser runner because the Chrome extension API is
available inside Codex, not as a general standalone Node API. Do not replace it with mouse/keyboard
automation. The runner must claim the exact URL, verify the composer, submit once, harvest one
matching receipt, and release the tab.

## Recovery

- Offline endpoint: retain `queued`.
- Wrong workspace or host: reject before lease.
- Duplicate receipt: return the existing immutable receipt.
- Expired lease: retry with the same message ID and a new attempt event.
- Browser login/CAPTCHA/usage gate: mark blocked; do not loop.
- Popup or visible-shell regression: enable kill switch and route runtime repair separately.
- Supervisor crash after intent: compare PID plus process start time; recover a valid durable stdout
  receipt or requeue only after proving the child is gone.
- Missing resumable session: rotate to a new UUID, increment registry version, and retry.
- Provider/auth/network outage: retain queued work and report degraded; authentication requires an
  owner button before the endpoint returns to ready.
