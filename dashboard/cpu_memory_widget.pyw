import ctypes
import tkinter as tk
from tkinter import font


REFRESH_MS = 1000

# Customize your widget here.
WIDGET_TITLE = "ZDH Monitor"
WINDOW_ALPHA = 0.88
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

# Set this to 1.0 for the original size. 0.5 is half-size.
UI_SCALE = 0.5


def scaled(value):
    return max(1, round(value * UI_SCALE))


class FILETIME(ctypes.Structure):
    _fields_ = [
        ("dwLowDateTime", ctypes.c_ulong),
        ("dwHighDateTime", ctypes.c_ulong),
    ]


class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong),
        ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong),
        ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong),
        ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong),
        ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


kernel32 = ctypes.windll.kernel32
user32 = ctypes.windll.user32


def filetime_to_int(value):
    return (value.dwHighDateTime << 32) + value.dwLowDateTime


class SystemSampler:
    def __init__(self):
        self.previous_idle = None
        self.previous_total = None

    def cpu_percent(self):
        idle = FILETIME()
        kernel = FILETIME()
        user = FILETIME()

        if not kernel32.GetSystemTimes(
            ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user)
        ):
            return 0.0

        idle_now = filetime_to_int(idle)
        kernel_now = filetime_to_int(kernel)
        user_now = filetime_to_int(user)
        total_now = kernel_now + user_now

        if self.previous_idle is None:
            self.previous_idle = idle_now
            self.previous_total = total_now
            return 0.0

        idle_delta = idle_now - self.previous_idle
        total_delta = total_now - self.previous_total
        self.previous_idle = idle_now
        self.previous_total = total_now

        if total_delta <= 0:
            return 0.0

        busy_delta = total_delta - idle_delta
        return max(0.0, min(100.0, (busy_delta / total_delta) * 100.0))

    def memory(self):
        status = MEMORYSTATUSEX()
        status.dwLength = ctypes.sizeof(MEMORYSTATUSEX)

        if not kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return 0, 0, 0.0

        total_gb = status.ullTotalPhys / (1024**3)
        used_gb = (status.ullTotalPhys - status.ullAvailPhys) / (1024**3)
        return used_gb, total_gb, float(status.dwMemoryLoad)


class UsageWidget:
    def __init__(self):
        self.sampler = SystemSampler()
        self.root = tk.Tk()
        self.root.title("CPU and Memory")
        self.root.geometry("+40+40")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", WINDOW_ALPHA)
        self.root.configure(bg=BACKGROUND_COLOR)
        self.root.protocol("WM_DELETE_WINDOW", self.root.destroy)

        self.drag_start_x = 0
        self.drag_start_y = 0

        self.base_font = font.Font(family="Segoe UI", size=scaled(11))
        self.label_font = font.Font(
            family="Segoe UI", size=scaled(11), weight="bold"
        )
        self.value_font = font.Font(
            family="Segoe UI", size=scaled(20), weight="bold"
        )

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
        self.memory_detail.pack(fill="x", pady=(scaled(2), 0))

        self.cpu_bar = self.progress_bar(CPU_COLOR)
        self.memory_bar = self.progress_bar(MEMORY_COLOR)

        for widget in (self.frame, self.header, self.title, self.content):
            widget.bind("<ButtonPress-1>", self.start_drag)
            widget.bind("<B1-Motion>", self.drag)

        self.root.bind("<Escape>", lambda _event: self.root.destroy())
        self.keep_on_screen()
        self.refresh()

    def metric_row(self, label_text, color):
        row = tk.Frame(self.content, bg=BACKGROUND_COLOR)
        row.pack(fill="x", pady=(0, scaled(4)))

        label = tk.Label(
            row,
            text=label_text,
            fg=TEXT_COLOR,
            bg=BACKGROUND_COLOR,
            font=self.label_font,
            width=scaled(8),
            anchor="w",
        )
        label.pack(side="left")

        value = tk.Label(
            row,
            text="0%",
            fg=color,
            bg=BACKGROUND_COLOR,
            font=self.value_font,
            width=scaled(6),
            anchor="e",
        )
        value.pack(side="right")
        return value

    def progress_bar(self, color):
        bar_width = scaled(220)
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

    def refresh(self):
        cpu = self.sampler.cpu_percent()
        used_gb, total_gb, memory_percent = self.sampler.memory()

        self.cpu_value.config(text=f"{cpu:.0f}%")
        self.memory_value.config(text=f"{memory_percent:.0f}%")
        self.memory_detail.config(text=f"{used_gb:.1f} GB / {total_gb:.1f} GB")

        self.update_bar(self.cpu_bar, cpu)
        self.update_bar(self.memory_bar, memory_percent)

        self.root.after(REFRESH_MS, self.refresh)

    def start_drag(self, event):
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

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    UsageWidget().run()
