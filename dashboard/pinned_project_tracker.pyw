import ctypes
import json
import os
import subprocess
import sys
import time
import tkinter as tk
from pathlib import Path
from tkinter import font


REFRESH_MS = 30000
WIDGET_TITLE = "ZDH Project Tracker"
WINDOW_ALPHA = 0.88
START_TOP_OFFSET = 150
START_RIGHT_OFFSET = 28

BACKGROUND_COLOR = "#07090d"
PANEL_COLOR = "#0d1117"
BORDER_COLOR = "#263241"
TEXT_COLOR = "#c9d1d9"
MUTED_TEXT_COLOR = "#6e7681"
ACTIVE_SECONDS = 90
STALE_SECONDS = 300
HOT_SECONDS = 300
HOT_ACTIVITY_COUNT = 8
AUTO_DISCOVER_SECONDS = STALE_SECONDS
AUTO_KEEP_SECONDS = 900
AUTO_MAX_PROJECTS = 8
AUTO_SCAN_DEPTH = 5
AUTO_ROOT_SCAN_DEPTH = 2
GIT_TIMEOUT_SECONDS = 2
OWNER_BUTTON_QUEUE = Path.home() / ".codex" / "queues" / "owner-buttons.json"

ACTIVE_COLOR = "#4fa36a"
HOT_COLOR = "#d66f2f"
IDLE_COLOR = "#c0a34a"
STALE_COLOR = "#b4555d"
ERROR_COLOR = "#b4555d"
BAR_BACKGROUND_COLOR = "#161b22"
CLOSE_HOVER_COLOR = "#5f1f2a"

UI_SCALE = 1.0
CONFIG_FILE = "pinned_projects.json"
CONFIG_DIR = Path.home() / ".codex" / "dashboard"
NON_PROJECT_FOLDER_NAMES = {
    "desktop",
    "documents",
    "downloads",
    "onedrive",
    "repos",
    "repositories",
    "zdh dashboard",
    "zdh dashboard app",
    "_internal",
}
PROJECT_MARKERS = {
    ".git",
    "package.json",
    "pyproject.toml",
    "requirements.txt",
    "vite.config.js",
    "next.config.js",
    "index.html",
}


user32 = ctypes.windll.user32


def scaled(value):
    return max(1, round(value * UI_SCALE))


def app_dir():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def codex_sessions_dir():
    return Path.home() / ".codex" / "sessions"


def dashboard_config_path():
    return CONFIG_DIR / CONFIG_FILE


def short_path(path):
    text = str(path)
    if len(text) <= 36:
        return text
    return "..." + text[-33:]


def format_age(seconds):
    if seconds < 60:
        return "now"
    if seconds < 3600:
        return f"{round(seconds / 60)}m"
    return f"{round(seconds / 3600)}h"


def format_duration(seconds):
    if seconds is None:
        return ""
    if seconds < 60:
        return "<1m"
    if seconds < 3600:
        return f"{round(seconds / 60)}m"
    return f"{round(seconds / 3600)}h"


class ProjectState:
    def __init__(
        self,
        name,
        path,
        status,
        detail,
        color,
        activity_count=0,
        branch="",
        dirty_count=None,
        last_push="",
        owner_button_count=0,
        owner_button_labels=None,
        age_seconds=None,
        stale_seconds=STALE_SECONDS,
    ):
        self.name = name
        self.path = path
        self.status = status
        self.detail = detail
        self.color = color
        self.activity_count = activity_count
        self.branch = branch
        self.dirty_count = dirty_count
        self.last_push = last_push
        self.owner_button_count = owner_button_count
        self.owner_button_labels = owner_button_labels or []
        self.age_seconds = age_seconds
        self.stale_seconds = stale_seconds

    @property
    def display_status(self):
        if self.owner_button_count:
            return "OWNER"
        if self.color == STALE_COLOR:
            return f"\U0001f634 {format_duration(self.sleep_seconds)}"
        if self.status == "hot":
            return "🔥 HOT"
        if self.status == "working":
            return "🟢 LIVE"
        if self.status == "missing":
            return "⚠ OFFLINE"
        if self.status == "error":
            return "⚠ ERROR"
        if self.color == STALE_COLOR:
            return "😴 SLEEP"
        return "🟡 WAIT"

    @property
    def sleep_seconds(self):
        if self.age_seconds is None:
            return None
        return max(0, self.age_seconds - self.stale_seconds)

    @property
    def status_key(self):
        if self.owner_button_count:
            return "owner"
        if self.status in {"hot", "working", "missing", "error"}:
            return self.status
        if self.color == STALE_COLOR:
            return "sleep"
        return "wait"

    @property
    def sort_rank(self):
        if self.owner_button_count:
            return 0
        if self.status == "hot":
            return 1
        if self.status == "working":
            return 2
        if self.color == IDLE_COLOR:
            return 3
        if self.color == STALE_COLOR:
            return 4
        return 5

    @property
    def codex_summary(self):
        if self.owner_button_count:
            return "Codex: waiting on owner"
        if self.status in {"hot", "working"}:
            return "Codex: working"
        if self.status in {"missing", "error"}:
            return "Codex: needs attention"
        if self.status_key == "sleep":
            return f"Codex: sleeping {format_duration(self.sleep_seconds)}"
        return "Codex: waiting"

    @property
    def repo_summary(self):
        parts = []
        if self.branch:
            parts.append(f"branch {self.branch}")
        if self.dirty_count is not None:
            parts.append(f"{self.dirty_count} dirty")
        if self.last_push:
            parts.append(f"remote {self.last_push}")
        return " | ".join(parts)

    @property
    def owner_summary(self):
        if not self.owner_button_count:
            return ""
        labels = ", ".join(self.owner_button_labels[:2]) or "owner button"
        if self.owner_button_count > 2:
            labels += f" +{self.owner_button_count - 2}"
        return f"owner: {labels}"

    @property
    def detail_lines(self):
        first = " | ".join(
            part for part in [self.detail, self.repo_summary] if part
        )
        second = " | ".join(
            part for part in [self.codex_summary, self.owner_summary] if part
        )
        return [line for line in [first, second] if line]


class ProjectSampler:
    def __init__(self):
        self.config_path = dashboard_config_path()
        self.auto_project_cache = {}
        self.session_file_cache = None
        self.owner_buttons_cache = None

    def load_config(self):
        if not self.config_path.exists():
            self.create_or_migrate_config()

        try:
            data = json.loads(self.config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

        if not isinstance(data, dict):
            return {}
        return data

    def create_or_migrate_config(self):
        self.config_path.parent.mkdir(parents=True, exist_ok=True)

        legacy_path = app_dir() / CONFIG_FILE
        if legacy_path.exists() and legacy_path != self.config_path:
            try:
                content = legacy_path.read_text(encoding="utf-8")
                data = json.loads(content)
            except (OSError, json.JSONDecodeError):
                data = None

            if isinstance(data, dict):
                self.config_path.write_text(content, encoding="utf-8")
                return

        self.config_path.write_text(
            json.dumps(
                {
                    "auto_discover": True,
                    "projects": [],
                },
                indent=2,
            ),
            encoding="utf-8",
        )

    def load_projects(self):
        data = self.load_config()

        projects = data.get("projects", [])
        if not isinstance(projects, list):
            return []
        return projects

    def sample(self):
        self.session_file_cache = None
        self.owner_buttons_cache = None
        config = self.load_config()
        projects = self.configured_projects(config)
        projects.extend(self.discover_auto_projects(config, projects))

        if not projects:
            return [
                ProjectState(
                    "No projects",
                    "",
                    "idle",
                    f"Edit {CONFIG_FILE}",
                    IDLE_COLOR,
                )
            ]

        states = [self.sample_project(project) for project in projects]
        return sorted(states, key=lambda state: (state.sort_rank, state.name.lower()))

    def configured_projects(self, config):
        projects = config.get("projects", [])
        if not isinstance(projects, list):
            return []
        return [
            project
            for project in projects
            if isinstance(project, dict) and not self.is_container_project(project)
        ]

    def discover_auto_projects(self, config, configured_projects):
        if config.get("auto_discover", True) is False:
            return []

        now = time.time()
        discover_seconds = int(
            config.get("auto_discover_seconds") or AUTO_DISCOVER_SECONDS
        )
        keep_seconds = int(config.get("auto_keep_seconds") or AUTO_KEEP_SECONDS)
        max_projects = int(config.get("auto_max_projects") or AUTO_MAX_PROJECTS)
        scan_depth = int(config.get("auto_scan_depth") or AUTO_SCAN_DEPTH)
        root_scan_depth = int(
            config.get("auto_root_scan_depth") or AUTO_ROOT_SCAN_DEPTH
        )
        cutoff = now - discover_seconds
        known_paths = self.project_path_keys(configured_projects)
        known_roots = self.existing_project_roots(configured_projects)

        for root in self.auto_discovery_roots(config, configured_projects):
            for folder in self.iter_project_candidates(root, root_scan_depth):
                key = self.path_key(folder)
                if key in known_paths:
                    continue
                if self.is_non_project_name(folder.name):
                    continue
                if self.is_dashboard_app_path(folder):
                    continue
                if self.is_inside_existing_project(folder, known_roots):
                    continue

                folder_scan_depth = scan_depth if self.looks_like_project(folder) else 2
                newest_mtime = self.latest_file_mtime(
                    folder,
                    max_depth=folder_scan_depth,
                    newer_than=cutoff,
                    stop_at_first_newer=True,
                )
                if newest_mtime is None:
                    continue

                self.auto_project_cache[key] = {
                    "name": self.auto_project_name(folder),
                    "path": str(folder),
                    "last_seen": max(
                        newest_mtime,
                        self.auto_project_cache.get(key, {}).get("last_seen", 0),
                    ),
                }

        keep_cutoff = now - keep_seconds
        self.auto_project_cache = {
            key: cached
            for key, cached in self.auto_project_cache.items()
            if cached.get("last_seen", 0) >= keep_cutoff and key not in known_paths
        }

        cached_projects = sorted(
            self.auto_project_cache.values(),
            key=lambda item: item.get("last_seen", 0),
            reverse=True,
        )[:max_projects]

        return [
            {
                "name": item["name"],
                "path": item["path"],
                "active_seconds": ACTIVE_SECONDS,
                "stale_seconds": STALE_SECONDS,
                "session_terms": [item["name"], item["path"]],
            }
            for item in cached_projects
        ]

    def auto_discovery_roots(self, config, configured_projects):
        raw_roots = config.get("auto_discover_roots")
        roots = []

        if isinstance(raw_roots, list):
            roots.extend(Path(str(root)) for root in raw_roots if str(root).strip())

        for project in configured_projects:
            for path in self.project_paths(project):
                if path.exists():
                    roots.append(path.parent)

        roots.extend(
            [
                Path.home() / "OneDrive" / "Documents",
                Path.home() / "OneDrive" / "Desktop",
                Path.home() / "Documents",
                Path.home() / "Desktop",
                Path("C:/repos"),
            ]
        )

        unique_roots = []
        seen = set()
        for root in roots:
            try:
                resolved = root.resolve()
            except OSError:
                continue

            key = str(resolved).lower()
            if key in seen or not resolved.exists() or not resolved.is_dir():
                continue
            seen.add(key)
            unique_roots.append(resolved)

        return unique_roots

    def iter_project_candidates(self, root, max_depth=1):
        ignored_names = {
            "$recycle.bin",
            ".git",
            ".venv",
            "__pycache__",
            "_internal",
            "build",
            "dist",
            "node_modules",
        }

        root = Path(root)
        for current, dirs, _files in os.walk(root):
            current_path = Path(current)
            try:
                depth = len(current_path.relative_to(root).parts)
            except ValueError:
                continue

            dirs[:] = [
                name
                for name in sorted(dirs, key=str.lower)
                if name.lower() not in ignored_names and not name.startswith(".")
            ]
            if depth >= max_depth:
                dirs[:] = []
            if depth == 0:
                continue

            yield current_path

    def looks_like_project(self, folder):
        return any((folder / marker).exists() for marker in PROJECT_MARKERS)

    def is_non_project_name(self, name):
        normalized = str(name).strip().lower()
        if normalized in NON_PROJECT_FOLDER_NAMES:
            return True
        if normalized == "new project":
            return True
        if normalized.startswith("new project "):
            suffix = normalized.removeprefix("new project ").strip()
            return suffix.isdigit()
        return False

    def is_container_project(self, project):
        name = str(project.get("name") or "").strip()
        if name and not self.is_non_project_name(name):
            return False

        paths = self.project_paths(project)
        if not paths:
            return False
        return all(self.is_non_project_name(path.name) for path in paths)

    def is_dashboard_app_path(self, path):
        try:
            resolved = Path(path).resolve()
            own_dir = app_dir().resolve()
        except OSError:
            return False
        return resolved == own_dir or own_dir in resolved.parents

    def project_path_keys(self, projects):
        keys = set()
        for project in projects:
            for path in self.project_paths(project):
                keys.add(self.path_key(path))
        return keys

    def existing_project_roots(self, projects):
        roots = []
        for project in projects:
            for path in self.project_paths(project):
                try:
                    if path.exists():
                        roots.append(path.resolve())
                except OSError:
                    continue
        return roots

    def is_inside_existing_project(self, path, known_roots):
        try:
            resolved = Path(path).resolve()
        except OSError:
            return False
        return any(resolved == root or root in resolved.parents for root in known_roots)

    def project_paths(self, project):
        raw_paths = project.get("paths")
        if not isinstance(raw_paths, list):
            raw_paths = [project.get("path")]
        return [Path(str(path)) for path in raw_paths if path]

    def path_key(self, path):
        try:
            return str(Path(path).resolve()).lower()
        except OSError:
            return str(path).lower()

    def auto_project_name(self, folder):
        name = folder.name.replace("-", " ").replace("_", " ").strip()
        return " ".join(word.capitalize() for word in name.split()) or folder.name

    def sample_project(self, project):
        name = str(project.get("name") or "Project")
        active_seconds = int(project.get("active_seconds") or ACTIVE_SECONDS)
        stale_seconds = int(project.get("stale_seconds") or STALE_SECONDS)
        session_terms = [
            str(term).lower()
            for term in project.get("session_terms", [])
            if str(term).strip()
        ]
        include_dirs = {
            str(name)
            for name in project.get("include_dirs", [])
            if str(name).strip()
        }
        paths = self.project_paths(project)
        session_terms.extend(str(path).lower() for path in paths)

        existing_paths = [path for path in paths if path.exists()]
        display_path = str(paths[0]) if paths else ""
        owner_buttons = self.owner_buttons_for_project(name, paths, session_terms)
        owner_labels = [
            str(item.get("Site") or item.get("Project") or "owner button")
            for item in owner_buttons
        ]
        repo_info = self.git_info(existing_paths)
        state_kwargs = {
            "branch": repo_info.get("branch", ""),
            "dirty_count": repo_info.get("dirty_count"),
            "last_push": repo_info.get("last_push", ""),
            "owner_button_count": len(owner_buttons),
            "owner_button_labels": owner_labels,
        }

        def status_color(color):
            return ERROR_COLOR if owner_buttons else color

        if not existing_paths:
            return ProjectState(
                name,
                display_path,
                "missing",
                "folder not found",
                status_color(ERROR_COLOR),
                **state_kwargs,
            )

        session_mtime = self.latest_codex_session_mtime(session_terms)
        newest_mtime = session_mtime
        activity_count = 1 if session_mtime else 0
        for path in existing_paths:
            path_mtime, recent_count = self.file_activity(path, HOT_SECONDS, include_dirs)
            if path_mtime is not None and (
                newest_mtime is None or path_mtime > newest_mtime
            ):
                newest_mtime = path_mtime
            activity_count += recent_count

        if newest_mtime is None:
            return ProjectState(
                name,
                display_path,
                "idle",
                "no files found",
                status_color(IDLE_COLOR),
                **state_kwargs,
            )

        age = max(0, time.time() - newest_mtime)
        detail = f"last update {format_age(age)}"
        age_kwargs = {"age_seconds": age, "stale_seconds": stale_seconds}

        if age <= active_seconds and activity_count >= HOT_ACTIVITY_COUNT:
            return ProjectState(
                name,
                display_path,
                "hot",
                detail,
                status_color(HOT_COLOR),
                activity_count,
                **age_kwargs,
                **state_kwargs,
            )

        if age <= active_seconds:
            return ProjectState(
                name,
                display_path,
                "working",
                detail,
                status_color(ACTIVE_COLOR),
                activity_count,
                **age_kwargs,
                **state_kwargs,
            )

        if age >= stale_seconds:
            return ProjectState(
                name,
                display_path,
                "idle",
                detail,
                status_color(STALE_COLOR),
                activity_count,
                **age_kwargs,
                **state_kwargs,
            )

        return ProjectState(
            name,
            display_path,
            "idle",
            detail,
            status_color(IDLE_COLOR),
            activity_count,
            **age_kwargs,
            **state_kwargs,
        )

    def git_info(self, paths):
        for path in paths:
            root = self.git_output(["rev-parse", "--show-toplevel"], path)
            if not root:
                continue

            branch = self.git_output(["branch", "--show-current"], root)
            if not branch:
                branch = self.git_output(["rev-parse", "--short", "HEAD"], root)

            status = self.git_output(["status", "--short"], root)
            dirty_count = len([line for line in status.splitlines() if line.strip()])

            upstream = self.git_output(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
                root,
            )
            last_push = ""
            if upstream:
                last_push = self.git_output(["log", "-1", "--format=%cr", upstream], root)
            elif self.git_output(["rev-parse", "--verify", "--quiet", "origin/main"], root):
                last_push = self.git_output(["log", "-1", "--format=%cr", "origin/main"], root)

            return {
                "branch": branch.strip(),
                "dirty_count": dirty_count,
                "last_push": last_push.strip(),
            }

        return {}

    def git_output(self, args, cwd):
        try:
            completed = subprocess.run(
                ["git", *args],
                cwd=str(cwd),
                capture_output=True,
                text=True,
                timeout=GIT_TIMEOUT_SECONDS,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        except (OSError, subprocess.SubprocessError):
            return ""
        if completed.returncode != 0:
            return ""
        return completed.stdout.strip()

    def load_owner_buttons(self):
        if self.owner_buttons_cache is not None:
            return self.owner_buttons_cache
        if not OWNER_BUTTON_QUEUE.exists():
            self.owner_buttons_cache = []
            return self.owner_buttons_cache
        try:
            data = json.loads(OWNER_BUTTON_QUEUE.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            self.owner_buttons_cache = []
            return self.owner_buttons_cache
        if isinstance(data, dict):
            data = [data]
        if not isinstance(data, list):
            self.owner_buttons_cache = []
            return self.owner_buttons_cache
        self.owner_buttons_cache = [
            item
            for item in data
            if isinstance(item, dict) and str(item.get("Status", "")).lower() == "open"
        ]
        return self.owner_buttons_cache

    def owner_buttons_for_project(self, name, paths, terms):
        tokens = {name.lower()}
        tokens.update(str(term).lower() for term in terms if str(term).strip())
        for path in paths:
            tokens.add(str(path).lower())
            tokens.add(Path(path).name.lower())
        tokens = {token for token in tokens if token}

        matches = []
        for item in self.load_owner_buttons():
            haystack = " ".join(
                str(item.get(field, ""))
                for field in ("Project", "Site", "Needed", "Why", "Next")
            ).lower()
            if any(token in haystack or haystack in token for token in tokens):
                matches.append(item)
        return matches

    def latest_codex_session_mtime(self, terms):
        if not terms:
            return None

        session_files = self.latest_codex_session_files()
        if not session_files:
            return None

        newest = None
        for mtime, content in session_files:
            if any(term in content for term in terms):
                if newest is None or mtime > newest:
                    newest = mtime

        return newest

    def latest_codex_session_files(self):
        if self.session_file_cache is not None:
            return self.session_file_cache

        sessions_dir = codex_sessions_dir()
        if not sessions_dir.exists():
            self.session_file_cache = []
            return self.session_file_cache

        try:
            files = sorted(
                sessions_dir.rglob("*.jsonl"),
                key=lambda file: file.stat().st_mtime,
                reverse=True,
            )[:20]
        except OSError:
            self.session_file_cache = []
            return self.session_file_cache

        session_files = []
        for file_path in files:
            try:
                stat = file_path.stat()
                content = self.read_tail(file_path).lower()
            except OSError:
                continue
            session_files.append((stat.st_mtime, content))

        self.session_file_cache = session_files
        return self.session_file_cache

    def read_tail(self, file_path, max_bytes=2_000_000):
        size = file_path.stat().st_size
        with file_path.open("rb") as file:
            if size > max_bytes:
                file.seek(-max_bytes, os.SEEK_END)
            return file.read().decode("utf-8", errors="ignore")

    def latest_file_mtime(
        self,
        path,
        include_dirs=None,
        max_depth=None,
        newer_than=None,
        stop_at_first_newer=False,
    ):
        newest = None
        include_dirs = include_dirs or set()
        ignored_dirs = {
            ".git",
            ".next",
            ".cache",
            ".venv",
            "__pycache__",
            "build",
            "dist",
            "node_modules",
        }
        ignored_dirs -= include_dirs

        path = Path(path)
        for root, dirs, files in os.walk(path):
            if max_depth is not None:
                try:
                    depth = len(Path(root).relative_to(path).parts)
                except ValueError:
                    depth = 0
                if depth >= max_depth:
                    dirs[:] = []

            dirs[:] = [name for name in dirs if name not in ignored_dirs]
            for file_name in files:
                file_path = Path(root) / file_name
                try:
                    mtime = file_path.stat().st_mtime
                except OSError:
                    continue
                if newer_than is not None and mtime < newer_than:
                    continue
                if stop_at_first_newer:
                    return mtime
                if newest is None or mtime > newest:
                    newest = mtime
        return newest

    def recent_file_activity_count(self, path, seconds, include_dirs=None):
        _newest, count = self.file_activity(path, seconds, include_dirs)
        return count

    def file_activity(self, path, seconds, include_dirs=None):
        cutoff = time.time() - seconds
        newest = None
        count = 0
        include_dirs = include_dirs or set()
        ignored_dirs = {
            ".git",
            ".next",
            ".cache",
            ".venv",
            "__pycache__",
            "build",
            "dist",
            "node_modules",
        }
        ignored_dirs -= include_dirs

        for root, dirs, files in os.walk(path):
            dirs[:] = [name for name in dirs if name not in ignored_dirs]
            for file_name in files:
                try:
                    mtime = (Path(root) / file_name).stat().st_mtime
                    if newest is None or mtime > newest:
                        newest = mtime
                    if mtime >= cutoff:
                        count += 1
                except OSError:
                    continue
        return newest, count


class ProjectTrackerWidget:
    def __init__(self):
        self.sampler = ProjectSampler()
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

        self.base_font = font.Font(family="Segoe UI", size=scaled(10))
        self.label_font = font.Font(
            family="Segoe UI", size=scaled(11), weight="bold"
        )
        self.status_font = font.Font(
            family="Segoe UI", size=scaled(13), weight="bold"
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

        self.rows = []

        for widget in (self.frame, self.header, self.title, self.content):
            widget.bind("<ButtonPress-1>", self.start_drag)
            widget.bind("<B1-Motion>", self.drag)

        self.root.bind("<Escape>", lambda _event: self.root.destroy())
        self.keep_on_screen()
        self.refresh()

    def rebuild_rows(self, states):
        for row in self.rows:
            row.destroy()
        self.rows = []

        for state in states:
            row = tk.Frame(self.content, bg=BACKGROUND_COLOR)
            row.pack(fill="x", pady=(0, scaled(5)))

            top = tk.Frame(row, bg=BACKGROUND_COLOR)
            top.pack(fill="x")

            name = tk.Label(
                top,
                text=state.name[:34],
                fg=TEXT_COLOR,
                bg=BACKGROUND_COLOR,
                font=self.label_font,
                anchor="w",
                width=22,
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

            for detail_text in state.detail_lines:
                detail = tk.Label(
                    row,
                    text=detail_text[:74],
                    fg=MUTED_TEXT_COLOR,
                    bg=BACKGROUND_COLOR,
                    font=self.base_font,
                    anchor="w",
                )
                detail.pack(fill="x", padx=(scaled(4), 0))

            self.rows.append(row)

    def refresh(self):
        self.rebuild_rows(self.sampler.sample())
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
    ProjectTrackerWidget().run()
