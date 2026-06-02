import atexit
import base64
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


if sys.stdout is None:
    sys.stdout = open(os.devnull, "w", encoding="utf-8")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w", encoding="utf-8")

BASE_DIR = Path(__file__).resolve().parent
HOST = "127.0.0.1"
PORT = int(os.environ.get("CUSTOM_UI_PORT", "4187"))
CODEX_PORT = int(os.environ.get("CUSTOM_UI_CODEX_PORT", "14567"))
CODEX_LISTEN = f"ws://{HOST}:{CODEX_PORT}"
MODEL = os.environ.get("CUSTOM_UI_MODEL", "gpt-5.2")
CODEX_PROCESS = None
CODEX_ERROR = None
CODEX_LOG = []
CODEX_SESSION = None
SKIP_GIT_DIRS = {
    ".app-profile",
    ".git",
    ".venv",
    "__pycache__",
    "dist",
    "node_modules",
}
TURN_SAFETY_RULES = """Workspace safety rules:
- Before reading or editing project files, verify the workspace Git repo is clean and current with GitHub.
- Fetch before work, fast-forward only when the repo is clean and strictly behind its upstream.
- If the repo is dirty, ahead, diverged, detached, or missing an upstream, stop and tell the user before editing.
- Before any commit or push, repeat the Git status/fetch/upstream checks and make sure the reviewed version includes the latest GitHub state.
- Do not mix files, branches, or worktrees from another chat's workspace.
"""


def find_codex_exe():
    configured = os.environ.get("CUSTOM_UI_CODEX_PATH")
    if configured and Path(configured).is_file():
        return configured

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        bin_root = Path(local_app_data) / "OpenAI" / "Codex" / "bin"
        matches = sorted(
            bin_root.glob("*/codex.exe"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if matches:
            return str(matches[0])

    return shutil.which("codex")


def capture_codex_output(pipe, stream_name):
    try:
        for line in iter(pipe.readline, ""):
            CODEX_LOG.append(f"{stream_name}: {line.rstrip()}")
            del CODEX_LOG[:-30]
    except ValueError:
        return


def codex_ready():
    try:
        with socket.create_connection((HOST, CODEX_PORT), timeout=0.5) as connection:
            connection.sendall(
                b"GET /readyz HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Connection: close\r\n\r\n"
            )
            status_line = connection.recv(128).splitlines()[0]
            return b" 200 " in status_line
    except (OSError, IndexError, TimeoutError):
        return False


def ensure_codex_bridge():
    global CODEX_PROCESS, CODEX_ERROR

    if codex_ready():
        CODEX_ERROR = None
        return True

    if CODEX_PROCESS and CODEX_PROCESS.poll() is None:
        return False

    codex_exe = find_codex_exe()
    if not codex_exe:
        CODEX_ERROR = "codex.exe was not found. Set CUSTOM_UI_CODEX_PATH to the Codex CLI path."
        return False

    try:
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
        CODEX_PROCESS = subprocess.Popen(
            [codex_exe, "app-server", "--listen", CODEX_LISTEN],
            cwd=str(BASE_DIR),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=creationflags,
        )
    except OSError as error:
        CODEX_ERROR = str(error)
        return False

    threading.Thread(
        target=capture_codex_output,
        args=(CODEX_PROCESS.stdout, "stdout"),
        daemon=True,
    ).start()
    threading.Thread(
        target=capture_codex_output,
        args=(CODEX_PROCESS.stderr, "stderr"),
        daemon=True,
    ).start()

    for _ in range(40):
        if codex_ready():
            CODEX_ERROR = None
            return True
        if CODEX_PROCESS.poll() is not None:
            CODEX_ERROR = CODEX_LOG[-1] if CODEX_LOG else "codex app-server exited during startup."
            return False
        time.sleep(0.25)

    CODEX_ERROR = f"codex app-server did not become ready on {CODEX_LISTEN}."
    return False


def stop_codex_bridge():
    if not CODEX_PROCESS or CODEX_PROCESS.poll() is not None:
        return
    CODEX_PROCESS.terminate()
    try:
        CODEX_PROCESS.wait(timeout=2)
    except subprocess.TimeoutExpired:
        CODEX_PROCESS.kill()


atexit.register(stop_codex_bridge)


class WorkspaceSyncError(RuntimeError):
    def __init__(self, message, workspace=None):
        super().__init__(message)
        self.workspace = workspace or {}


def run_git(args, cwd, timeout=30, allow_fail=False):
    git_exe = shutil.which("git")
    if not git_exe:
        raise WorkspaceSyncError("Git was not found, so this workspace cannot be checked safely.")

    completed = subprocess.run(
        [git_exe, *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if completed.returncode != 0 and not allow_fail:
        detail = (completed.stderr or completed.stdout or "git command failed").strip()
        raise WorkspaceSyncError(detail)
    return completed


def git_output(args, cwd, timeout=30, allow_fail=False):
    completed = run_git(args, cwd, timeout=timeout, allow_fail=allow_fail)
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def inside_git_root(path):
    result = run_git(["rev-parse", "--show-toplevel"], path, allow_fail=True)
    if result.returncode != 0:
        return None
    root = result.stdout.strip()
    if not root:
        return None

    root_path = Path(root).resolve()
    path = Path(path).resolve()
    try:
        distance = len(path.relative_to(root_path).parts)
    except ValueError:
        return None

    if distance > 2:
        return None
    return str(root_path)


def nested_git_roots(path, max_depth=3, max_dirs=250, include_self=True):
    roots = []
    base = Path(path).resolve()
    if not base.is_dir():
        return roots

    checked = 0
    for current, dirs, _files in os.walk(base):
        current_path = Path(current)
        depth = len(current_path.relative_to(base).parts)
        dirs[:] = [name for name in dirs if name not in SKIP_GIT_DIRS]
        if depth >= max_depth:
            dirs[:] = []

        is_base = current_path == base
        if (current_path / ".git").exists() and (include_self or not is_base):
            roots.append(str(current_path.resolve()))
            dirs[:] = []

        checked += 1
        if checked >= max_dirs:
            break

    return roots


def workspace_git_roots(cwd):
    if not cwd:
        return []

    path = Path(cwd)
    if not path.exists():
        raise WorkspaceSyncError(f"Workspace does not exist: {cwd}", {"cwd": cwd, "ok": False})

    root = inside_git_root(path)
    roots = [root] if root else []
    if path.is_dir():
        roots.extend(nested_git_roots(path, include_self=not root))
    unique = []
    for item in roots:
        if item and item not in unique:
            unique.append(item)
    return unique


def check_repo_synced(repo_root):
    repo = Path(repo_root)
    branch = git_output(["branch", "--show-current"], repo, allow_fail=True) or ""
    status = git_output(["status", "--porcelain"], repo, allow_fail=True) or ""
    remote_url = git_output(["remote", "get-url", "origin"], repo, allow_fail=True) or ""

    result = {
        "repo": str(repo),
        "branch": branch or "detached",
        "remote": remote_url,
        "upstream": None,
        "action": "clean",
        "ok": True,
    }

    if status.strip():
        result["ok"] = False
        result["action"] = "dirty"
        raise WorkspaceSyncError(
            f"Workspace has uncommitted changes in {repo}. Commit or stash them before opening this chat.",
            result,
        )

    remotes = git_output(["remote"], repo, allow_fail=True) or ""
    if not remotes.strip():
        result["action"] = "no remote"
        return result

    if not branch:
        result["ok"] = False
        result["action"] = "detached"
        raise WorkspaceSyncError(
            f"{repo} is on a detached HEAD, so I cannot compare it to GitHub safely.",
            result,
        )

    run_git(["fetch", "--all", "--prune"], repo, timeout=90)
    upstream = git_output(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], repo, allow_fail=True)
    if not upstream and "origin" in remotes.splitlines():
        candidate = f"origin/{branch}"
        exists = run_git(["show-ref", "--verify", "--quiet", f"refs/remotes/{candidate}"], repo, allow_fail=True)
        if exists.returncode == 0:
            upstream = candidate

    if not upstream:
        result["ok"] = False
        result["action"] = "no upstream"
        raise WorkspaceSyncError(
            f"{repo} has no GitHub tracking branch for {branch}. Set an upstream before using this chat.",
            result,
        )

    result["upstream"] = upstream
    counts = git_output(["rev-list", "--left-right", "--count", f"HEAD...{upstream}"], repo)
    ahead, behind = [int(part) for part in counts.split()]
    result["ahead"] = ahead
    result["behind"] = behind

    if ahead and behind:
        result["ok"] = False
        result["action"] = "diverged"
        raise WorkspaceSyncError(
            f"{repo} has diverged from {upstream}. Resolve that before using this chat.",
            result,
        )

    if ahead:
        result["ok"] = False
        result["action"] = "ahead"
        raise WorkspaceSyncError(
            f"{repo} has local commits that are not on GitHub. Push them before using this chat.",
            result,
        )

    if behind:
        run_git(["merge", "--ff-only", upstream], repo, timeout=90)
        result["action"] = f"fast-forwarded {behind} commit{'s' if behind != 1 else ''}"
        result["behind"] = 0

    after_status = git_output(["status", "--porcelain"], repo, allow_fail=True) or ""
    if after_status.strip():
        result["ok"] = False
        result["action"] = "dirty after sync"
        raise WorkspaceSyncError(
            f"{repo} became dirty after syncing. Review the worktree before using this chat.",
            result,
        )

    result["head"] = git_output(["rev-parse", "--short", "HEAD"], repo, allow_fail=True) or ""
    return result


def ensure_workspace_synced(cwd):
    workspace = {"cwd": cwd or "", "ok": True, "checked": False, "repos": []}
    roots = workspace_git_roots(cwd)
    if not roots:
        workspace["action"] = "no git repo"
        return workspace

    workspace["checked"] = True
    for root in roots:
        workspace["repos"].append(check_repo_synced(root))
    workspace["action"] = ", ".join(repo["action"] for repo in workspace["repos"])
    return workspace


class LocalWebSocket:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sock = None

    def connect(self):
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        self.sock = socket.create_connection((self.host, self.port), timeout=10)
        request = (
            "GET / HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        self.sock.sendall(request.encode("ascii"))
        response = self._recv_until(b"\r\n\r\n")
        if b" 101 " not in response.splitlines()[0]:
            raise RuntimeError("Codex websocket handshake failed.")

        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        if expected.encode("ascii") not in response:
            raise RuntimeError("Codex websocket accept key was invalid.")

    def close(self):
        if not self.sock:
            return
        try:
            self.sock.close()
        finally:
            self.sock = None

    def send_json(self, payload):
        self.send_text(json.dumps(payload, separators=(",", ":")))

    def send_text(self, text):
        data = text.encode("utf-8")
        mask = os.urandom(4)
        header = bytearray([0x81])
        length = len(data)
        if length < 126:
            header.append(0x80 | length)
        elif length <= 0xFFFF:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
        self.sock.sendall(bytes(header) + mask + masked)

    def recv_json(self, timeout=60):
        text = self.recv_text(timeout)
        return json.loads(text)

    def recv_text(self, timeout=60):
        self.sock.settimeout(timeout)
        chunks = []
        while True:
            opcode, payload = self._recv_frame()
            if opcode == 0x1:
                chunks.append(payload)
                return b"".join(chunks).decode("utf-8")
            if opcode == 0x0:
                chunks.append(payload)
                continue
            if opcode == 0x8:
                raise RuntimeError("Codex websocket closed.")
            if opcode == 0x9:
                self._send_control(0xA, payload)

    def _send_control(self, opcode, payload):
        mask = os.urandom(4)
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.sock.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)

    def _recv_frame(self):
        first = self._recv_exact(2)
        opcode = first[0] & 0x0F
        masked = bool(first[1] & 0x80)
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]

        mask = self._recv_exact(4) if masked else None
        payload = self._recv_exact(length)
        if mask:
            payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        return opcode, payload

    def _recv_exact(self, length):
        chunks = bytearray()
        while len(chunks) < length:
            chunk = self.sock.recv(length - len(chunks))
            if not chunk:
                raise RuntimeError("Socket closed while reading Codex websocket.")
            chunks.extend(chunk)
        return bytes(chunks)

    def _recv_until(self, marker):
        data = bytearray()
        while marker not in data:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("Socket closed during websocket handshake.")
            data.extend(chunk)
        return bytes(data)


class CodexSession:
    def __init__(self):
        self.lock = threading.Lock()
        self.ws = None
        self.next_id = 1
        self.thread_id = None
        self.thread_cwd = str(BASE_DIR)
        self.initialized = False

    def reset(self):
        if self.ws:
            self.ws.close()
        self.ws = None
        self.thread_id = None
        self.thread_cwd = str(BASE_DIR)
        self.initialized = False

    def connect(self):
        if self.ws and self.initialized:
            return

        if not ensure_codex_bridge():
            raise RuntimeError(CODEX_ERROR or "Codex bridge is not ready.")

        self.ws = LocalWebSocket(HOST, CODEX_PORT)
        self.ws.connect()
        self.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "custom-ui-server",
                    "title": "Custom UI",
                    "version": "0.1.0",
                },
                "capabilities": {
                    "experimentalApi": True,
                    "requestAttestation": False,
                    "optOutNotificationMethods": [],
                },
            },
            timeout=15,
        )
        self.initialized = True

    def start_new_thread(self, model):
        self.connect()
        started = self.request(
            "thread/start",
            {
                "cwd": str(BASE_DIR),
                "runtimeWorkspaceRoots": [str(BASE_DIR)],
                "model": model,
                "approvalPolicy": "never",
                "sandbox": "workspace-write",
                "sessionStartSource": "startup",
                "threadSource": "user",
                "experimentalRawEvents": False,
            },
            timeout=20,
        )
        self.thread_id = started.get("thread", {}).get("id")
        if not self.thread_id:
            raise RuntimeError("Codex did not return a thread id.")
        self.thread_cwd = started.get("cwd") or started.get("thread", {}).get("cwd") or str(BASE_DIR)
        return started

    def resume_thread(self, thread_id, model):
        self.connect()
        resumed = self.request(
            "thread/resume",
            {
                "threadId": thread_id,
                "model": model,
                "approvalPolicy": "never",
                "sandbox": "workspace-write",
                "excludeTurns": True,
            },
            timeout=30,
        )
        thread = resumed.get("thread") or {}
        self.thread_id = thread.get("id") or thread_id
        self.thread_cwd = resumed.get("cwd") or thread.get("cwd") or str(BASE_DIR)
        return resumed

    def request(self, method, params, timeout=30):
        request_id = self.next_id
        self.next_id += 1
        self.ws.send_json({"id": request_id, "method": method, "params": params})
        while True:
            message = self.ws.recv_json(timeout)
            if message.get("id") != request_id:
                continue
            if message.get("error"):
                raise RuntimeError(json.dumps(message["error"]))
            return message.get("result")

    def list_threads(self, limit=80, search_term=None):
        with self.lock:
            self.connect()
            params = {
                "limit": limit,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "archived": False,
            }
            if search_term:
                params["searchTerm"] = search_term
            result = self.request("thread/list", params, timeout=20)
            threads = [simplify_thread(thread, self.thread_id) for thread in result.get("data", [])]
            return {"threads": threads, "nextCursor": result.get("nextCursor")}

    def read_thread_messages(self, thread_id):
        self.connect()
        result = self.request(
            "thread/read",
            {"threadId": thread_id, "includeTurns": True},
            timeout=30,
        )
        thread = result.get("thread") or {}
        return {
            "thread": simplify_thread(thread, self.thread_id),
            "messages": thread_messages(thread),
        }

    def select_thread(self, thread_id, model):
        with self.lock:
            preview = self.read_thread_messages(thread_id)
            workspace = ensure_workspace_synced(preview.get("thread", {}).get("cwd") or str(BASE_DIR))
            self.resume_thread(thread_id, model)
            selected = self.read_thread_messages(thread_id)
            selected["workspace"] = workspace
            return selected

    def create_thread(self, model):
        with self.lock:
            return self.start_new_thread(model)

    def send_chat(self, messages, model, thread_id=None):
        text = chat_text(messages)
        if not text:
            raise RuntimeError("No user message was provided.")

        with self.lock:
            try:
                if thread_id and thread_id != self.thread_id:
                    self.resume_thread(thread_id, model)
                elif not self.thread_id:
                    self.start_new_thread(model)
            except Exception:
                self.reset()
                if thread_id:
                    self.resume_thread(thread_id, model)
                else:
                    self.start_new_thread(model)

            workspace = ensure_workspace_synced(self.thread_cwd)
            protected_text = protected_turn_text(text, workspace)

            try:
                result = self.start_turn(protected_text, model)
            except Exception:
                self.reset()
                if thread_id:
                    self.resume_thread(thread_id, model)
                else:
                    self.start_new_thread(model)
                workspace = ensure_workspace_synced(self.thread_cwd)
                protected_text = protected_turn_text(text, workspace)
                result = self.start_turn(protected_text, model)

            result["workspace"] = workspace
            return result

    def start_turn(self, text, model):
        request_id = self.next_id
        self.next_id += 1
        self.ws.send_json(
            {
                "id": request_id,
                "method": "turn/start",
                "params": {
                    "threadId": self.thread_id,
                    "input": [{"type": "text", "text": text, "text_elements": []}],
                    "approvalPolicy": "never",
                    "model": model,
                },
            }
        )

        reply = []
        while True:
            message = self.ws.recv_json(timeout=180)
            if message.get("id") == request_id and message.get("error"):
                raise RuntimeError(json.dumps(message["error"]))

            method = message.get("method")
            params = message.get("params") or {}
            if method == "item/agentMessage/delta":
                reply.append(params.get("delta") or "")
            elif method == "turn/completed":
                turn = params.get("turn") or {}
                if turn.get("status") == "completed":
                    return {
                        "reply": "".join(reply).strip() or "Done.",
                        "threadId": self.thread_id,
                        "cwd": self.thread_cwd,
                    }
                error = turn.get("error") or {}
                raise RuntimeError(error.get("message") or f"Turn ended with status {turn.get('status')}.")


def simplify_thread(thread, active_thread_id=None):
    title = thread.get("name") or thread.get("preview") or "Untitled chat"
    preview = thread.get("preview") or ""
    cwd = thread.get("cwd") or ""
    return {
        "id": thread.get("id"),
        "title": str(title).strip()[:120],
        "preview": str(preview).strip()[:220],
        "cwd": cwd,
        "updatedAt": thread.get("updatedAt"),
        "createdAt": thread.get("createdAt"),
        "source": thread.get("source"),
        "active": thread.get("id") == active_thread_id,
    }


def thread_messages(thread):
    rows = []
    for turn in thread.get("turns") or []:
        for item in turn.get("items") or []:
            item_type = item.get("type")
            if item_type == "userMessage":
                text = user_message_text(item.get("content") or [])
                if text:
                    rows.append({"role": "user", "title": "You", "body": text})
            elif item_type == "agentMessage":
                text = str(item.get("text") or "").strip()
                if text:
                    rows.append({"role": "codex", "title": "Codex", "body": text})
    return rows[-80:]


def user_message_text(content):
    parts = []
    for item in content:
        if item.get("type") == "text" and item.get("text"):
            parts.append(str(item["text"]).strip())
    return "\n".join(part for part in parts if part)


def chat_text(messages):
    clean = []
    for message in messages[-12:]:
        role = message.get("role")
        content = str(message.get("content") or "").strip()
        if role in {"user", "assistant"} and content:
            clean.append((role, content))

    if not clean:
        return ""

    latest = next((content for role, content in reversed(clean) if role == "user"), clean[-1][1])
    history = "\n".join(f"{role.title()}: {content}" for role, content in clean[:-1])
    if history:
        return f"Conversation so far:\n{history}\n\nCurrent user message:\n{latest}"
    return latest


def protected_turn_text(text, workspace):
    workspace_lines = [TURN_SAFETY_RULES.strip(), "", "Workspace preflight:"]
    workspace_lines.append(f"- cwd: {workspace.get('cwd') or 'unknown'}")
    workspace_lines.append(f"- status: {workspace.get('action') or 'checked'}")
    for repo in workspace.get("repos") or []:
        workspace_lines.append(
            "- repo: "
            f"{repo.get('repo')} | "
            f"branch: {repo.get('branch')} | "
            f"upstream: {repo.get('upstream') or 'none'} | "
            f"action: {repo.get('action')} | "
            f"head: {repo.get('head') or 'unknown'}"
        )
    workspace_lines.append("")
    workspace_lines.append("User request:")
    workspace_lines.append(text)
    return "\n".join(workspace_lines)


CODEX_SESSION = CodexSession()


class CustomUiHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        if self.path == "/api/status":
            codex_connected = ensure_codex_bridge()
            codex_pid = (
                CODEX_PROCESS.pid
                if CODEX_PROCESS and CODEX_PROCESS.poll() is None
                else None
            )
            self.write_json(
                {
                    "connected": codex_connected,
                    "mode": "codex" if codex_connected else "local",
                    "model": MODEL,
                    "codexWebSocket": CODEX_LISTEN if codex_connected else None,
                    "cwd": str(BASE_DIR),
                    "activeThreadId": CODEX_SESSION.thread_id,
                    "bridge": {
                        "pid": codex_pid,
                        "port": CODEX_PORT,
                        "ready": codex_connected,
                        "error": CODEX_ERROR,
                    },
                }
            )
            return
        if self.path.startswith("/api/threads"):
            try:
                threads = CODEX_SESSION.list_threads()
            except Exception as error:
                self.write_json({"error": str(error)}, status=502)
                return
            self.write_json(threads)
            return
        super().do_GET()

    def do_POST(self):
        if self.path not in {"/api/chat", "/api/thread/select", "/api/thread/new"}:
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            messages = payload.get("messages", [])
            model = payload.get("model") or MODEL
        except (ValueError, json.JSONDecodeError):
            self.write_json({"error": "Invalid JSON payload."}, status=400)
            return

        if self.path == "/api/thread/select":
            thread_id = str(payload.get("threadId") or "").strip()
            if not thread_id:
                self.write_json({"error": "threadId is required."}, status=400)
                return
            try:
                selected = CODEX_SESSION.select_thread(thread_id, model)
            except WorkspaceSyncError as error:
                self.write_json({"error": str(error), "workspace": error.workspace}, status=409)
                return
            except Exception as error:
                self.write_json({"error": str(error)}, status=502)
                return
            self.write_json(selected)
            return

        if self.path == "/api/thread/new":
            try:
                started = CODEX_SESSION.create_thread(model)
                thread = started.get("thread") or {}
            except Exception as error:
                self.write_json({"error": str(error)}, status=502)
                return
            self.write_json({"thread": simplify_thread(thread, CODEX_SESSION.thread_id), "messages": []})
            return

        try:
            result = CODEX_SESSION.send_chat(messages, model, payload.get("threadId"))
        except WorkspaceSyncError as error:
            self.write_json(
                {"error": str(error), "workspace": error.workspace, "mode": "codex", "model": model},
                status=409,
            )
            return
        except Exception as error:
            self.write_json({"error": str(error), "mode": "codex", "model": model}, status=502)
            return

        self.write_json(
            {
                "reply": result["reply"],
                "mode": "codex",
                "model": model,
                "threadId": result.get("threadId"),
                "cwd": result.get("cwd"),
                "workspace": result.get("workspace"),
            }
        )

    def write_json(self, payload, status=200):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ensure_codex_bridge()
    print(f"Custom UI chat server: http://{HOST}:{PORT}")
    print(f"Codex bridge: {CODEX_LISTEN}")
    ThreadingHTTPServer((HOST, PORT), CustomUiHandler).serve_forever()
