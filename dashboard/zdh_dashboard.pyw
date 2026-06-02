import ctypes
import os
import subprocess
import sys
import time
import tkinter as tk
from pathlib import Path
from tkinter import font

from cpu_memory_widget import SystemSampler
from pinned_project_tracker import ProjectSampler


SYSTEM_REFRESH_MS = 1000
PROJECT_REFRESH_MS = 30000
ALERT_DURATION_MS = 7000
TOPMOST_REFRESH_MS = 5000
CODEX_TOPMOST_PAUSE_SECONDS = 10
CODEX_FOCUS_RETRY_MS = 1400
DRAGON_CLICK_COUNT = 4
DRAGON_CLICK_WINDOW_MS = 1600
DRAGON_DURATION_MS = 1000
DRAGON_EMOJI_SIZE = 136
DRAGON_CAPTION_SIZE = 17

WIDGET_TITLE = "ZDH Dashboard"
SINGLE_INSTANCE_MUTEX_NAME = "ZDH_Dashboard_Single_Instance"
WINDOW_ALPHA = 0.9
START_TOP_OFFSET = 28
START_RIGHT_OFFSET = 28

BACKGROUND_COLOR = "#07090d"
PANEL_COLOR = "#0d1117"
BORDER_COLOR = "#263241"
TEXT_COLOR = "#c9d1d9"
MUTED_TEXT_COLOR = "#6e7681"
CPU_COLOR = "#4f8cc9"
MEMORY_COLOR = "#5aa47a"
BAR_BACKGROUND_COLOR = "#161b22"
CLOSE_HOVER_COLOR = "#5f1f2a"
ALERT_BG_COLOR = "#18130d"
ALERT_TEXT_COLOR = "#f0c674"
DRAGON_BG_COLOR = "#130b06"
DRAGON_TEXT_COLOR = "#ff9f1c"
DRAGON_CAPTION_COLOR = "#ffd166"
ACTION_LOG_FILE = "zdh_dashboard_actions.log"

UI_SCALE = 1.0


user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
single_instance_mutex = None


def scaled(value):
    return max(1, round(value * UI_SCALE))


def is_already_running():
    global single_instance_mutex
    kernel32.SetLastError(0)
    single_instance_mutex = kernel32.CreateMutexW(
        None, True, SINGLE_INSTANCE_MUTEX_NAME
    )
    return kernel32.GetLastError() == 183


def find_codex_exe():
    env_path = os.environ.get("CODEX_CLI_PATH")
    if env_path and Path(env_path).exists():
        return str(Path(env_path).resolve())

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        bin_root = Path(local_app_data) / "OpenAI" / "Codex" / "bin"
        candidates = list(bin_root.glob("*/codex.exe"))
        direct_exe = bin_root / "codex.exe"
        if direct_exe.exists():
            candidates.append(direct_exe)

        candidates = sorted(
            [path for path in candidates if path.exists()],
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if candidates:
            return str(candidates[0])

    return None


def find_codex_desktop_exe():
    env_path = os.environ.get("CODEX_DESKTOP_PATH")
    if env_path and Path(env_path).exists():
        return str(Path(env_path).resolve())

    candidates = []

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        local_candidates = [
            Path(local_app_data) / "Programs" / "Codex" / "Codex.exe",
            Path(local_app_data) / "OpenAI" / "Codex" / "Codex.exe",
        ]
        candidates.extend(local_candidates)

    program_files = os.environ.get("ProgramFiles")
    if program_files:
        windows_apps = Path(program_files) / "WindowsApps"
        try:
            candidates.extend(windows_apps.glob("OpenAI.Codex_*\\app\\Codex.exe"))
        except OSError:
            pass

    existing = [path for path in candidates if path.exists()]
    existing.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    if existing:
        return str(existing[0].resolve())

    return None


def dashboard_app_dir():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def log_action(message):
    try:
        log_path = dashboard_app_dir() / ACTION_LOG_FILE
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with log_path.open("a", encoding="utf-8") as log_file:
            log_file.write(f"[{stamp}] {message}\n")
    except OSError:
        pass


def action_log_path():
    return dashboard_app_dir() / ACTION_LOG_FILE


def focus_codex_window():
    matches = []

    enum_windows = user32.EnumWindows
    enum_windows_proc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    is_window_visible = user32.IsWindowVisible
    get_window_text_length = user32.GetWindowTextLengthW
    get_window_text = user32.GetWindowTextW

    def collect(hwnd, _lparam):
        if not is_window_visible(hwnd):
            return True

        length = get_window_text_length(hwnd)
        if length <= 0:
            return True

        buffer = ctypes.create_unicode_buffer(length + 1)
        get_window_text(hwnd, buffer, length + 1)
        title = buffer.value
        if "Codex" in title and WIDGET_TITLE not in title:
            matches.append(hwnd)
        return True

    enum_windows(enum_windows_proc(collect), 0)
    if not matches:
        return False

    hwnd = matches[0]
    user32.ShowWindow(hwnd, 9)
    user32.SetForegroundWindow(hwnd)
    return True


class ZDHDashboard:
    def __init__(self):
        self.system_sampler = SystemSampler()
        self.project_sampler = ProjectSampler()

        self.root = tk.Tk()
        self.root.title(WIDGET_TITLE)
        self.root.geometry("+40+40")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", WINDOW_ALPHA)
        self.root.configure(bg=BACKGROUND_COLOR)
        self.root.protocol("WM_DELETE_WINDOW", self.root.destroy)

        self.drag_start_x = 0
        self.drag_start_y = 0
        self.project_rows = []
        self.project_refresh_job = None
        self.alert_hide_job = None
        self.topmost_paused_until = 0
        self.dragon_hide_job = None
        self.dragon_click_times = []
        self.previous_project_statuses = {}

        self.base_font = font.Font(family="Segoe UI", size=scaled(10))
        self.label_font = font.Font(
            family="Segoe UI", size=scaled(11), weight="bold"
        )
        self.value_font = font.Font(
            family="Segoe UI", size=scaled(20), weight="bold"
        )
        self.status_font = font.Font(
            family="Segoe UI", size=scaled(13), weight="bold"
        )
        self.dot_font = font.Font(family="Segoe UI", size=scaled(17), weight="bold")

        self.frame = tk.Frame(
            self.root,
            bg=BACKGROUND_COLOR,
            highlightthickness=1,
            highlightbackground=BORDER_COLOR,
        )
        self.frame.pack(fill="both", expand=True)

        self.header = tk.Frame(self.frame, bg=PANEL_COLOR)
        self.header.pack(fill="x")

        self.title = tk.Label(
            self.header,
            text=WIDGET_TITLE,
            fg=TEXT_COLOR,
            bg=PANEL_COLOR,
            font=self.label_font,
            padx=scaled(10),
            pady=scaled(6),
        )
        self.title.pack(side="left")

        self.refresh_button = tk.Button(
            self.header,
            text="↻",
            command=self.refresh_projects,
            width=scaled(3),
            relief="flat",
            bd=0,
            bg=PANEL_COLOR,
            fg=MUTED_TEXT_COLOR,
            activebackground=BORDER_COLOR,
            activeforeground=TEXT_COLOR,
            font=self.base_font,
        )
        self.refresh_button.pack(side="right")

        self.close_button = tk.Button(
            self.header,
            text="x",
            command=self.root.destroy,
            width=scaled(3),
            relief="flat",
            bd=0,
            bg=PANEL_COLOR,
            fg=MUTED_TEXT_COLOR,
            activebackground=CLOSE_HOVER_COLOR,
            activeforeground="#ffffff",
            font=self.base_font,
        )
        self.close_button.pack(side="right")

        self.content = tk.Frame(
            self.frame,
            bg=BACKGROUND_COLOR,
            padx=scaled(12),
            pady=scaled(10),
        )
        self.content.pack(fill="both", expand=True)

        self.cpu_value = self.metric_row("CPU", CPU_COLOR)
        self.memory_value = self.metric_row("MEM", MEMORY_COLOR)
        self.memory_detail = tk.Label(
            self.content,
            text="",
            fg=MUTED_TEXT_COLOR,
            bg=BACKGROUND_COLOR,
            font=self.base_font,
            anchor="w",
        )
        self.memory_detail.pack(fill="x", pady=(scaled(2), scaled(2)))

        self.cpu_bar = self.progress_bar(CPU_COLOR)
        self.memory_bar = self.progress_bar(MEMORY_COLOR)

        self.separator = tk.Frame(self.content, bg=BORDER_COLOR, height=1)
        self.separator.pack(fill="x", pady=(scaled(4), scaled(8)))

        self.projects_title = tk.Label(
            self.content,
            text="PROJECTS",
            fg=MUTED_TEXT_COLOR,
            bg=BACKGROUND_COLOR,
            font=self.base_font,
            anchor="w",
        )
        self.projects_title.pack(fill="x", pady=(0, scaled(6)))

        self.projects = tk.Frame(self.content, bg=BACKGROUND_COLOR)
        self.projects.pack(fill="both", expand=True)

        self.alert = tk.Label(
            self.content,
            text="",
            fg=ALERT_TEXT_COLOR,
            bg=ALERT_BG_COLOR,
            font=self.label_font,
            anchor="w",
            padx=scaled(8),
            pady=scaled(6),
        )

        self.dragon_font = font.Font(
            family="Segoe UI Emoji", size=scaled(DRAGON_EMOJI_SIZE), weight="bold"
        )
        self.dragon_caption_font = font.Font(
            family="Segoe UI", size=scaled(DRAGON_CAPTION_SIZE), weight="bold"
        )
        self.dragon_overlay = tk.Frame(
            self.frame,
            bg=DRAGON_BG_COLOR,
        )
        self.dragon_badge = tk.Label(
            self.dragon_overlay,
            text="\U0001f409",
            fg=DRAGON_TEXT_COLOR,
            bg=DRAGON_BG_COLOR,
            font=self.dragon_font,
            anchor="center",
        )
        self.dragon_badge.pack(expand=True, pady=(scaled(4), 0))

        self.dragon_caption = tk.Label(
            self.dragon_overlay,
            text="ZDH DRAGON MODE",
            fg=DRAGON_CAPTION_COLOR,
            bg=DRAGON_BG_COLOR,
            font=self.dragon_caption_font,
            anchor="center",
        )
        self.dragon_caption.pack(fill="x", pady=(0, scaled(14)))

        for widget in (
            self.frame,
            self.header,
            self.title,
            self.content,
            self.projects_title,
            self.projects,
        ):
            widget.bind("<ButtonPress-1>", self.start_drag)
            widget.bind("<B1-Motion>", self.drag)

        self.root.bind("<Escape>", lambda _event: self.root.destroy())
        self.keep_on_screen()
        self.refresh_system()
        self.refresh_projects()
        self.enforce_topmost()

    def metric_row(self, label_text, color):
        row = tk.Frame(self.content, bg=BACKGROUND_COLOR)
        row.pack(fill="x", pady=(0, scaled(4)))

        label = tk.Label(
            row,
            text=label_text,
            fg=TEXT_COLOR,
            bg=BACKGROUND_COLOR,
            font=self.label_font,
            width=8,
            anchor="w",
        )
        label.pack(side="left")

        value = tk.Label(
            row,
            text="0%",
            fg=color,
            bg=BACKGROUND_COLOR,
            font=self.value_font,
            width=6,
            anchor="e",
        )
        value.pack(side="right")
        return value

    def progress_bar(self, color):
        bar_width = scaled(260)
        bar_height = scaled(8)
        canvas = tk.Canvas(
            self.content,
            width=bar_width,
            height=bar_height,
            bg=BACKGROUND_COLOR,
            highlightthickness=0,
            bd=0,
        )
        canvas.pack(fill="x", pady=(0, scaled(10)))
        canvas.create_rectangle(
            0, 0, bar_width, bar_height, fill=BAR_BACKGROUND_COLOR, outline=""
        )
        fill = canvas.create_rectangle(0, 0, 0, bar_height, fill=color, outline="")
        return canvas, fill, bar_height

    def update_bar(self, bar, percent):
        canvas, fill, bar_height = bar
        width = max(1, canvas.winfo_width())
        canvas.coords(fill, 0, 0, width * (percent / 100.0), bar_height)

    def refresh_system(self):
        cpu = self.system_sampler.cpu_percent()
        used_gb, total_gb, memory_percent = self.system_sampler.memory()

        self.cpu_value.config(text=f"{cpu:.0f}%")
        self.memory_value.config(text=f"{memory_percent:.0f}%")
        self.memory_detail.config(text=f"{used_gb:.1f} GB / {total_gb:.1f} GB")

        self.update_bar(self.cpu_bar, cpu)
        self.update_bar(self.memory_bar, memory_percent)

        self.root.after(SYSTEM_REFRESH_MS, self.refresh_system)

    def refresh_projects(self):
        states = self.project_sampler.sample()
        self.handle_project_transitions(states)
        self.rebuild_project_rows(states)

        if self.project_refresh_job is not None:
            try:
                self.root.after_cancel(self.project_refresh_job)
            except tk.TclError:
                pass
        self.project_refresh_job = self.root.after(PROJECT_REFRESH_MS, self.refresh_projects)

    def handle_project_transitions(self, states):
        next_statuses = {state.name: state.status_key for state in states}
        if not self.previous_project_statuses:
            self.previous_project_statuses = next_statuses
            return

        messages = []
        for state in states:
            old_status = self.previous_project_statuses.get(state.name)
            new_status = state.status_key
            if old_status is None and new_status in {"hot", "working"}:
                messages.append(f"\U0001f7e2 {state.name} added")
                continue
            if old_status and old_status != new_status:
                message = self.transition_message(state.name, old_status, new_status)
                if message:
                    messages.append(message)

        self.previous_project_statuses = next_statuses
        if messages:
            self.show_alert("  |  ".join(messages[:2]))

    def transition_message(self, name, old_status, new_status):
        if new_status == "owner":
            return f"{name} needs owner"
        if new_status == "hot":
            return f"\U0001f525 {name} is hot"
        if new_status == "working" and old_status in {
            "wait",
            "sleep",
            "missing",
            "error",
        }:
            return f"\U0001f7e2 {name} woke up"
        if new_status == "wait" and old_status in {"working", "hot"}:
            return f"\U0001f7e1 {name} went quiet"
        if new_status == "sleep":
            return f"\U0001f634 {name} went to sleep"
        if new_status in {"missing", "error"}:
            return f"\u26a0 {name} needs attention"
        return f"{name}: {new_status}"

        if "HOT" in new_status:
            return f"🔥 {name} is hot"
        if "LIVE" in new_status and (
            "WAIT" in old_status or "SLEEP" in old_status or "OFFLINE" in old_status
        ):
            return f"🟢 {name} woke up"
        if "WAIT" in new_status and ("LIVE" in old_status or "HOT" in old_status):
            return f"🟡 {name} went quiet"
        if "SLEEP" in new_status:
            return f"😴 {name} went to sleep"
        if "OFFLINE" in new_status or "ERROR" in new_status:
            return f"⚠ {name} needs attention"
        return f"{name}: {new_status}"

    def show_alert(self, message, lift=True):
        if self.alert_hide_job is not None:
            try:
                self.root.after_cancel(self.alert_hide_job)
            except tk.TclError:
                pass

        self.alert.config(text=message)
        if not self.alert.winfo_manager():
            self.alert.pack(fill="x", pady=(scaled(8), 0))
        self.alert_hide_job = self.root.after(ALERT_DURATION_MS, self.hide_alert)
        if lift:
            self.root.attributes("-topmost", True)
            self.root.lift()

    def hide_alert(self):
        self.alert.pack_forget()
        self.alert_hide_job = None

    def rebuild_project_rows(self, states):
        for row in self.project_rows:
            row.destroy()
        self.project_rows = []

        for state in states:
            row = tk.Frame(self.projects, bg=BACKGROUND_COLOR)
            row.pack(fill="x", pady=(0, scaled(5)))
            row.bind("<ButtonPress-1>", self.start_drag)
            row.bind("<B1-Motion>", self.drag)

            top = tk.Frame(row, bg=BACKGROUND_COLOR)
            top.pack(fill="x")
            top.bind("<ButtonPress-1>", self.start_drag)
            top.bind("<B1-Motion>", self.drag)

            dot = tk.Label(
                top,
                text="●",
                fg=state.color,
                bg=BACKGROUND_COLOR,
                font=self.dot_font,
                anchor="w",
                width=2,
            )
            dot.pack(side="left")
            dot.bind("<ButtonPress-1>", self.start_drag)
            dot.bind("<B1-Motion>", self.drag)

            name = tk.Button(
                top,
                text=state.name[:34],
                command=lambda item=state: self.open_project_in_codex(item),
                fg=TEXT_COLOR,
                bg=BACKGROUND_COLOR,
                activeforeground="#ffffff",
                activebackground=BORDER_COLOR,
                font=self.label_font,
                anchor="w",
                width=20,
                cursor="hand2",
                relief="flat",
                bd=0,
                highlightthickness=0,
                padx=0,
                pady=0,
                takefocus=0,
            )
            name.pack(side="left")

            status = tk.Label(
                top,
                text=state.display_status,
                fg=state.color,
                bg=BACKGROUND_COLOR,
                font=self.status_font,
                anchor="e",
                width=9,
            )
            status.pack(side="right")
            status.bind("<ButtonPress-1>", self.start_drag)
            status.bind("<B1-Motion>", self.drag)

            for detail_text in state.detail_lines:
                detail = tk.Label(
                    row,
                    text=detail_text[:74],
                    fg=MUTED_TEXT_COLOR,
                    bg=BACKGROUND_COLOR,
                    font=self.base_font,
                    anchor="w",
                )
                detail.pack(fill="x", padx=(scaled(28), 0))
                detail.bind("<ButtonPress-1>", self.start_drag)
                detail.bind("<B1-Motion>", self.drag)

            self.project_rows.append(row)

    def open_project_in_codex(self, state):
        log_action(f"name click: {state.name} -> {state.path}")
        project_path = Path(state.path).resolve()
        if not project_path.exists():
            log_action(f"missing path: {state.name} -> {project_path}")
            self.show_alert(f"Cannot open {state.name}: folder missing")
            return

        self.pause_topmost()
        self.show_alert(f"Opening Codex: {state.name}", lift=False)

        log_file = None

        try:
            log_file = action_log_path().open("ab")

            desktop_exe = find_codex_desktop_exe()
            if desktop_exe:
                log_file.write(
                    f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] launch codex desktop: {desktop_exe} --open-project {project_path}\n".encode(
                        "utf-8"
                    )
                )
                process = subprocess.Popen(
                    [desktop_exe, "--open-project", str(project_path)],
                    cwd=str(Path(desktop_exe).parent),
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=log_file,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                log_action(f"codex desktop pid: {process.pid}")
            else:
                codex_exe = find_codex_exe()
                if not codex_exe:
                    log_action("launch failed: Codex Desktop and CLI not found")
                    self.show_alert("Could not find the Codex launcher")
                    return

                log_file.write(
                    f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] fallback codex cli: {codex_exe} app {project_path}\n".encode(
                        "utf-8"
                    )
                )
                process = subprocess.Popen(
                    [codex_exe, "app", str(project_path)],
                    cwd=str(Path(codex_exe).parent),
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=log_file,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                log_action(f"codex cli fallback pid: {process.pid}")
        except OSError as exc:
            log_action(f"launch failed: {exc}")
            self.show_alert(f"Could not open Codex: {exc}")
            return
        finally:
            if log_file is not None:
                log_file.close()

        self.root.after(CODEX_FOCUS_RETRY_MS, self.focus_codex_after_launch)
        self.root.after(CODEX_FOCUS_RETRY_MS * 2, self.focus_codex_after_launch)

    def pause_topmost(self):
        self.topmost_paused_until = time.monotonic() + CODEX_TOPMOST_PAUSE_SECONDS
        try:
            self.root.attributes("-topmost", False)
        except tk.TclError:
            pass

    def focus_codex_after_launch(self):
        focused = focus_codex_window()
        log_action(f"focus Codex window: {focused}")

    def start_drag(self, event):
        self.record_dragon_click()
        self.drag_start_x = event.x
        self.drag_start_y = event.y

    def drag(self, event):
        x = self.root.winfo_x() + event.x - self.drag_start_x
        y = self.root.winfo_y() + event.y - self.drag_start_y
        self.root.geometry(f"+{x}+{y}")

    def keep_on_screen(self):
        self.root.update_idletasks()
        width = self.root.winfo_reqwidth()
        screen_width = user32.GetSystemMetrics(0)
        x = screen_width - width - START_RIGHT_OFFSET
        self.root.geometry(f"+{max(0, x)}+{START_TOP_OFFSET}")

    def enforce_topmost(self):
        if time.monotonic() >= self.topmost_paused_until:
            self.root.attributes("-topmost", True)
            self.root.lift()
        self.root.after(TOPMOST_REFRESH_MS, self.enforce_topmost)

    def record_dragon_click(self):
        current_ms = int(time.monotonic() * 1000)
        cutoff = current_ms - DRAGON_CLICK_WINDOW_MS
        self.dragon_click_times = [
            click_time for click_time in self.dragon_click_times if click_time >= cutoff
        ]
        self.dragon_click_times.append(current_ms)

        if len(self.dragon_click_times) >= DRAGON_CLICK_COUNT:
            self.dragon_click_times = []
            self.show_dragon()

    def show_dragon(self):
        if self.dragon_hide_job is not None:
            try:
                self.root.after_cancel(self.dragon_hide_job)
            except tk.TclError:
                pass

        self.dragon_overlay.place(relx=0, rely=0, relwidth=1, relheight=1)
        self.dragon_overlay.lift()
        self.root.attributes("-topmost", True)
        self.root.lift()
        self.dragon_hide_job = self.root.after(DRAGON_DURATION_MS, self.hide_dragon)

    def hide_dragon(self):
        self.dragon_overlay.place_forget()
        self.dragon_hide_job = None

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    if is_already_running():
        sys.exit(0)
    ZDHDashboard().run()
