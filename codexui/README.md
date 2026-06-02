# Custom UI

A standalone custom UI prototype for a fresh Codex-focused project.

## Run

Easiest download:

1. Download `dist/CustomUI-Windows.zip`.
2. Unzip it.
3. Double-click `Custom UI.exe`.

On Windows, double-click:

```text
Custom UI.exe
```

It starts the local server and opens `http://127.0.0.1:4187`.
The launcher opens it as a standalone Windows app window, without browser tabs
or an address bar.

If Windows warns because the executable is unsigned, choose **More info** and **Run anyway**.

You can still run the local server manually:

```powershell
cd codexui
python server.py
```

`Start Custom UI.bat` is kept as a fallback launcher.

The server starts a local Codex app-server bridge and the browser chat connects to it over
the local server. The Chats panel lists your recent Codex threads, lets you open an
existing chat, and sends new messages into the selected thread. Before opening a chat
or sending a message, the bridge checks that chat's Git workspace, fetches GitHub, and
only fast-forwards a clean branch. Dirty, ahead, or diverged worktrees are blocked so
one chat cannot mix into another chat's files. Every chat turn also includes explicit
safety rules that require Codex to re-check Git before editing files and again before
any commit or push. If Codex is installed in a custom location, set the path before
starting:

```powershell
setx CUSTOM_UI_CODEX_PATH "C:\path\to\codex.exe"
```

After setting it, open a new terminal and start the server again.

## Files

- `index.html` - app structure
- `styles.css` - responsive interface styling
- `app.js` - local interactions and chat switching
- `server.py` - local server and Codex app-server launcher
- `Custom UI.exe` - easiest Windows launcher
- `Start Custom UI.bat` - Windows fallback launcher
- `Build Windows EXE.bat` - rebuilds the launcher executable
- `launcher/CustomUILauncher.cs` - launcher source
- `assets/codex-workbench-map.png` - visual map asset
