# AI Manager

AI Manager is the conductor worker for Zev's project system.

Its job is to make sure the important projects are running, explain why they are not running when something breaks, report that clearly, and make bounded changes when the fix is safe and explicitly configured.

## Start Here

- `planning/STATE.md` - current project state and next action
- `planning/intake.md` - open product questions
- `planning/requirements.md` - draft requirements as they become known
- `planning/blueprint.md` - operating model for the manager worker
- `planning/live-projects.md` - how AI Manager should interact with Zev's live projects
- `projects.live.json` - default runnable live project registry

## First Command

Run a manager report:

```powershell
.\ai-manager\scripts\ai-manager.cmd
```

Use a local project inventory override when needed:

```powershell
Copy-Item .\ai-manager\projects.example.json .\ai-manager\projects.local.json
.\ai-manager\scripts\ai-manager.cmd -ConfigPath .\ai-manager\projects.local.json
```

`projects.local.json` is gitignored so machine-specific project paths and fix commands stay local.
