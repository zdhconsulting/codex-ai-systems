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

## Message states

`queued -> leased -> awaiting_receipt -> succeeded|blocked|failed`

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

Every accepted return must echo `message_id` and `correlation_id`, provide a terminal status,
summary, evidence, and next action.

## Endpoint kinds

- `codex_cli_session`: saved Codex task/session ID plus matching cwd.
- `claude_cli_session`: managed Claude Code session ID plus matching cwd.
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
