ZDH Dashboard

One always-on-top Windows widget for:
- CPU usage
- Memory usage
- Project activity
- Git branch, dirty file count, and last known remote commit age
- Owner-button blockers from C:\Users\zev\.codex\queues\owner-buttons.json
- Codex status: working, waiting, waiting on owner, or needs attention

How to run:
1. Double-click the "ZDH Dashboard" shortcut on your Desktop after it is built.
2. Or double-click "Start ZDH Dashboard.bat" from this folder.

Projects:
- The dashboard reads pinned projects from C:\Users\zev\.codex\dashboard\pinned_projects.json.
- If that file is missing, the dashboard migrates a valid pinned_projects.json from the app folder.
- Project activity refreshes every 30 seconds.
- CPU and memory refresh every second.
- Single-click a project name to create a fresh Codex chat for that repo and open it in Codex Desktop.
- The "LAST LAUNCH" receipt shows the last launched project, repo path, and fresh thread ID.
- Click and drag the rest of the row to move the dashboard.
- Statuses: 🔥 HOT, 🟢 LIVE, 🟡 WAIT, 😴 SLEEP, ⚠ OFFLINE/ERROR.
- Sleeping projects show how long they have been asleep.
- Active projects are sorted toward the top automatically.
- Recently active unpinned folders from Documents, Desktop, and C:\repos appear automatically.
- Auto-discovery checks shallow nested folders under those roots for new movement.
- Auto-discovered projects stay visible for up to 15 minutes so they can turn LIVE, WAIT, then SLEEP.
- Each project row now shows branch, dirty count, last known remote age, and Codex state.
- Projects with open owner-button blockers float to the top and show OWNER.
- A temporary alert appears when a project wakes up, goes hot, goes quiet, or goes to sleep.
- The dashboard periodically reasserts always-on-top so it stays visible.
- Click the dashboard 4 times quickly to trigger the 1-second dragon mode.
