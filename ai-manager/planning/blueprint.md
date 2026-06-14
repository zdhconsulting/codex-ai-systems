# AI Manager Blueprint

## Role

AI Manager is the conductor worker for Zev's project system.

It does not replace the specialist Codex workers. It watches the orchestra: projects, repos, dashboards, owner buttons, local processes, health checks, and next actions. When something is not running, it should answer three questions quickly:

1. What is not running?
2. Why is it not running?
3. What should happen next?

## Operating Loop

1. Load the project inventory.
2. Inspect each project for expected running signals.
3. Classify each project as `running`, `needs-attention`, or `not-running`.
4. Explain every warning and failure.
5. Report the whole picture compactly.
6. Run only safe, explicit fix commands when `-Fix` is passed.
7. Escalate owner-only and commander-only tasks using the existing workflow gates.

## Signals

- Project path exists.
- Git repository exists.
- Expected branch matches.
- Expected remote matches.
- Required files exist.
- Local process is running.
- Health URL responds.
- Check command exits successfully.
- Owner-button queue has no blocking item for the project.

## Failure Reasons

- Missing local path.
- Missing git repository.
- Wrong branch.
- Wrong remote.
- Dirty worktree that needs saving or review.
- Missing required file.
- Expected process is stopped.
- Health URL is down.
- Check command failed.
- Owner button is blocking progress.
- Commander approval is needed before a risky change.

## Change Policy

AI Manager can always inspect and report.

AI Manager can make changes only when one of these is true:

- The change is an explicit configured fix command and the operator passed `-Fix`.
- The change is a normal local Codex implementation step inside the active repo.
- Zev gives Commander approval for a risky strategic, production, permission, or repo-history action.
- Zev completes an owner-only action and the existing owner-button workflow gate is cleared.

## First Interface

The first interface is a local CLI report:

```powershell
.\ai-manager\scripts\ai-manager.cmd
```

Future interfaces can include a ZDH Dashboard panel, a scheduled background worker, and a Codex `Next` integration.
