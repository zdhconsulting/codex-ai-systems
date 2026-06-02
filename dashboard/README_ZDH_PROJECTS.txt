ZDH Projects

What it does:
- Shows pinned project folders in a small always-on-top Windows widget.
- Shows the name of each pinned project beside its current status.
- Refreshes every 30 seconds.
- Tracks recent file activity inside each pinned project folder.

How to run:
1. Double-click "ZDH Projects.exe" on your Desktop after it is built.
2. Or double-click "Start ZDH Projects.bat" from this folder.

How to choose pinned projects:
1. Edit "pinned_projects.json" in Notepad.
2. The "name" is the label that appears in the widget.
3. Add project entries like this:

{
  "name": "My App",
  "path": "C:\\Users\\zev\\Documents\\My App"
}

Status meanings:
- GREEN / WORKING: files changed in the last 90 seconds.
- YELLOW / IDLE: no file changes recently, but less than 5 minutes idle.
- RED / IDLE: no file changes for 5 minutes or more.
