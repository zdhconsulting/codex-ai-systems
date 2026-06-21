# Bosswoman Controller Mailbox

This is the durable control channel between AI Manager and the standalone Bosswoman controller on `MAYHASAPC`.

It exists because Codex thread messaging can hang and local desktop worker launches can become noisy. Both machines already have GitHub access, so this mailbox uses the shared `codex-ai-systems` repository as the reliable transport.

## Direction

- AI Manager to Bosswoman: `controller-mailbox/inbox/ai-manager-to-bosswoman.jsonl`
- Bosswoman to AI Manager: `controller-mailbox/outbox/bosswoman-to-ai-manager.jsonl`
- Bosswoman controller profile: `controller-mailbox/bosswoman-controller.json`

Bosswoman's Bossman runtime contract lives in:

- `C:\Repos\bossman\BOSSWOMAN_CONTROLLER.md`
- `C:\Repos\bossman\data\controller-profiles\bosswoman.mayhasapc.json`

Each line is one JSON packet. Packets are append-only and idempotent by `packet_id`.

## Packet Fields

- `packet_id`: unique stable id.
- `created_at`: UTC timestamp.
- `from`: sending lane or machine.
- `to`: receiving lane or machine.
- `type`: `command`, `status`, `return_packet`, `blocker`, or `critical`.
- `severity`: `routine`, `fyi`, `decision`, `blocker`, or `critical`.
- `project_scope`: project or list of projects.
- `requested_action`: short requested next action.
- `status`: `new`, `in_progress`, `done`, `blocked`, or `superseded`.
- `message`: human-readable instruction or response.
- `reply_to`: optional packet id being answered.
- `idempotency_key`: optional dedupe key for repeated automation ticks.

## AI Manager Send

From `C:\Repos\codex-ai-systems`:

```powershell
.\scripts\send-bosswoman-message.ps1 -Message "Inventory Mr SEO, ZDH Consulting, and ZDH Sales. Return repo paths, remotes, blockers, and safe runtime plan." -Severity decision -ProjectScope "Mr SEO,ZDH Consulting,ZDH Sales" -RequestedAction "inventory_and_return_plan" -Commit
```

## Bosswoman Read

On `MAYHASAPC`, from `C:\Repos\codex-ai-systems`:

```powershell
git pull --ff-only
.\scripts\bosswoman-mailbox-watch.ps1 -Once
```

## Bosswoman Auto-Notice Watcher

The durable setup is a hidden scheduled watcher on `MAYHASAPC`.

Install it once:

```powershell
cd C:\Repos\codex-ai-systems
git pull --ff-only
powershell -ExecutionPolicy Bypass -File scripts\install-bosswoman-mailbox-watcher.ps1 -LaunchCodex
```

What it does:

- pulls this repo every minute,
- detects new AI Manager packets for Bosswoman,
- writes an `in_progress` acknowledgement to the Bosswoman outbox,
- starts at most one hidden Bosswoman Codex controller run per tick,
- keeps a local dedupe/lock/log under `%LOCALAPPDATA%\ZDH\BosswomanMailbox`,
- avoids visible PowerShell windows.

Run one manual tick without Codex launch:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bosswoman-mailbox-tick.ps1
```

## Bosswoman Reply

On `MAYHASAPC`, from `C:\Repos\codex-ai-systems`:

```powershell
.\scripts\send-bosswoman-reply.ps1 -Message "Inventory complete..." -Status done -Commit
```

## AI Manager Read Replies

From `C:\Repos\codex-ai-systems`:

```powershell
.\scripts\read-bosswoman-outbox.ps1 -Pull
```

## Safety Contract

Bosswoman may inspect and prepare controller work for `Mr SEO`, `ZDH Consulting`, and `ZDH Sales`, but should not enable always-on runtime, deploy, change billing/security/DNS/secrets/permissions, or start broad worker fanout until AI Manager explicitly sends an approval packet.
