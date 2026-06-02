CPU and Memory Desktop Widget

How to run:
1. Double-click "dist\ZDH Monitor.exe".
2. Or double-click the "ZDH Monitor" shortcut on your Desktop.
2. Drag the widget by its top bar or body to move it.
3. Click "x" or press Esc while it is focused to close it.

Notes:
- The widget stays on top of other windows.
- It uses only Python's built-in libraries and Windows system APIs.
- If double-clicking does nothing, install Python for Windows from python.org and make sure "Add python.exe to PATH" is selected during installation.

How to customize it:
1. Right-click "cpu_memory_widget.pyw" and choose "Edit with Notepad".
2. Look near the top for "Customize your widget here."
3. Change WIDGET_TITLE, colors, transparency, and UI_SCALE.

Useful settings:
- UI_SCALE = 0.5 makes it about half-size.
- WINDOW_ALPHA controls transparency. Use 1.0 for solid, 0.75 for more see-through.
- CPU_COLOR and MEMORY_COLOR control the accent colors.
