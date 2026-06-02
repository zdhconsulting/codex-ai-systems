const body = document.body;
const navItems = Array.from(document.querySelectorAll(".nav-item"));
const timeline = document.querySelector("#timeline");
const terminalLog = document.querySelector("#terminalLog");
const runButton = document.querySelector("#runButton");
const clearButton = document.querySelector("#clearButton");
const chatForm = document.querySelector("#chatForm");
const chatInput = document.querySelector("#chatInput");
const themeToggle = document.querySelector("#themeToggle");
const palette = document.querySelector("#palette");
const paletteButton = document.querySelector("#paletteButton");
const paletteInput = document.querySelector("#paletteInput");
const paletteList = document.querySelector("#paletteList");
const planList = document.querySelector("#planList");
const planCount = document.querySelector("#planCount");
const planProgress = document.querySelector("#planProgress");
const fileList = document.querySelector("#fileList");
const addFileButton = document.querySelector("#addFileButton");
const threadList = document.querySelector("#threadList");
const refreshThreadsButton = document.querySelector("#refreshThreadsButton");
const newThreadButton = document.querySelector("#newThreadButton");
const sessionMode = document.querySelector("#sessionMode");
const viewTitle = document.querySelector("#viewTitle");
const localClock = document.querySelector("#localClock");
const connectionDot = document.querySelector("#connectionDot");
const connectionStatus = document.querySelector("#connectionStatus");
const serverMode = document.querySelector("#serverMode");
const activeModel = document.querySelector("#activeModel");
const modelSelect = document.querySelector("#modelSelect");
const activeThreadName = document.querySelector("#activeThreadName");
const projectButton = document.querySelector("#projectButton");

const DEFAULT_MODEL = "gpt-5.2";

const views = {
  chat: {
    mode: "Chat",
    title: "Custom UI",
    prompt: "Message Codex",
  },
  review: {
    mode: "Review",
    title: "Review Console",
    prompt: "Review the current UI for layout, accessibility, and responsive behavior.",
  },
  context: {
    mode: "Context",
    title: "Context Board",
    prompt: "Collect the relevant files, terminal output, browser notes, and open questions.",
  },
  ship: {
    mode: "Ship",
    title: "Ship Room",
    prompt: "Prepare a handoff summary with verification notes and next steps.",
  },
};

let activeView = "chat";
let fileIndex = 4;
let isSending = false;
let bridgeConfig = {
  connected: false,
  mode: "local",
  model: DEFAULT_MODEL,
  codexWebSocket: null,
  cwd: null,
};
let codexBridge = null;
let activeThreadId = null;
let threads = [];
let messages = [
  {
    role: "codex",
    title: "Codex",
    body: "I am here in Custom UI. Type below and this chat will route through the local Codex bridge when it is ready.",
    code: "workspace: codexui\nstatus: checking bridge",
  },
  {
    role: "system",
    title: "System",
    body: "Checking the local chat bridge.",
  },
];

function formatTime(date = new Date()) {
  return date.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function renderTimeline() {
  timeline.innerHTML = messages
    .map(
      (message) => `
        <article class="message${message.pending ? " is-pending" : ""}" data-role="${message.role}">
          <div class="message-header">
            <span class="message-role"><span class="role-dot" aria-hidden="true"></span>${escapeHtml(message.title)}</span>
            <time>${escapeHtml(message.time || formatTime())}</time>
          </div>
          <p>${escapeHtml(message.body)}</p>
          ${message.code ? `<pre class="message-code">${escapeHtml(message.code)}</pre>` : ""}
        </article>
      `,
    )
    .join("");
  timeline.scrollTop = timeline.scrollHeight;
}

function updateActiveThread(thread) {
  if (thread && Object.hasOwn(thread, "id")) {
    activeThreadId = thread.id || null;
  }
  const label = thread?.title || thread?.preview || "New chat";
  activeThreadName.textContent = label;
  viewTitle.textContent = label === "New chat" ? views[activeView].title : label;
  renderThreads();
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function appendTerminal(line) {
  const stamp = formatTime();
  terminalLog.textContent += `\n> ${stamp} ${line}`;
  terminalLog.scrollTop = terminalLog.scrollHeight;
}

function updatePlan() {
  const checks = Array.from(planList.querySelectorAll('input[type="checkbox"]'));
  const done = checks.filter((check) => check.checked).length;
  planCount.textContent = `${done}/${checks.length}`;
  planProgress.style.width = `${(done / checks.length) * 100}%`;
}

function advancePlan() {
  const next = Array.from(planList.querySelectorAll('input[type="checkbox"]')).find(
    (check) => !check.checked,
  );
  if (next) {
    next.checked = true;
    updatePlan();
  }
}

function chatPayload() {
  return messages
    .filter((message) => message.role === "user" || message.role === "codex")
    .filter((message) => !message.pending)
    .map((message) => ({
      role: message.role === "user" ? "user" : "assistant",
      content: message.body,
    }));
}

function threadSubtitle(thread) {
  const cwd = thread.cwd ? thread.cwd.split(/[\\/]/).filter(Boolean).slice(-2).join("/") : "codex";
  const rawUpdated = thread.updatedAt;
  const numericUpdated = Number(rawUpdated);
  const updatedDate = rawUpdated
    ? new Date(
        Number.isFinite(numericUpdated)
          ? numericUpdated > 100000000000
            ? numericUpdated
            : numericUpdated * 1000
          : rawUpdated,
      )
    : null;
  const updated = updatedDate && !Number.isNaN(updatedDate.getTime())
    ? updatedDate.toLocaleString([], {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })
    : "";
  return [cwd, updated].filter(Boolean).join(" / ");
}

function workspaceSummary(workspace) {
  if (!workspace) return "";
  if (!workspace.checked) return workspace.action || "no git repo";
  const repos = workspace.repos || [];
  if (!repos.length) return workspace.action || "checked";
  return repos
    .map((repo) => {
      const branch = repo.branch || "repo";
      const action = repo.action || "clean";
      const head = repo.head ? ` @ ${repo.head}` : "";
      return `${branch}: ${action}${head}`;
    })
    .join("; ");
}

function renderThreads() {
  if (!threadList) return;

  if (!threads.length) {
    threadList.innerHTML = `
      <button class="thread-row is-empty" type="button">
        <span>No chats found</span>
        <small>refresh</small>
      </button>
    `;
    return;
  }

  threadList.innerHTML = threads
    .map(
      (thread) => `
        <button class="thread-row${thread.id === activeThreadId ? " is-active" : ""}" type="button" data-thread-id="${escapeHtml(thread.id)}">
          <span>${escapeHtml(thread.title || "Untitled chat")}</span>
          <small>${escapeHtml(threadSubtitle(thread))}</small>
        </button>
      `,
    )
    .join("");
}

async function loadThreads() {
  if (!threadList) return;
  threadList.innerHTML = `
    <button class="thread-row is-empty" type="button">
      <span>Loading chats</span>
      <small>codex</small>
    </button>
  `;

  try {
    const response = await fetch("/api/threads");
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not load chats.");
    threads = payload.threads || [];
    const active = threads.find((thread) => thread.active) || threads.find((thread) => thread.id === activeThreadId);
    if (active) {
      updateActiveThread(active);
    } else {
      renderThreads();
    }
    appendTerminal(`chats loaded: ${threads.length}`);
  } catch (error) {
    threadList.innerHTML = `
      <button class="thread-row is-empty" type="button">
        <span>Chats unavailable</span>
        <small>${escapeHtml(error.message)}</small>
      </button>
    `;
    appendTerminal("chat list error");
  }
}

function apiMessagesToTimeline(nextMessages, thread) {
  const loaded = (nextMessages || []).map((message) => ({
    role: message.role === "user" ? "user" : "codex",
    title: message.title || (message.role === "user" ? "You" : "Codex"),
    body: message.body || "",
    time: "",
  }));

  if (!loaded.length) {
    return [
      {
        role: "system",
        title: "System",
        body: `Loaded ${thread?.title || "chat"}.`,
        time: formatTime(),
      },
    ];
  }

  return loaded;
}

async function selectThread(threadId) {
  if (!threadId || isSending) return;
  const thread = threads.find((item) => item.id === threadId);
  appendTerminal(`loading chat: ${thread?.title || threadId}`);
  appendTerminal("checking github snapshot");

  try {
    const response = await fetch("/api/thread/select", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ threadId, model: currentModel() }),
    });
    const payload = await response.json();
    if (!response.ok) {
      const error = new Error(payload.error || "Could not select chat.");
      error.workspace = payload.workspace;
      throw error;
    }
    activeThreadId = payload.thread?.id || threadId;
    messages = apiMessagesToTimeline(payload.messages, payload.thread || thread);
    updateActiveThread(payload.thread || thread);
    renderTimeline();
    appendTerminal("chat loaded");
    appendTerminal(`github snapshot: ${workspaceSummary(payload.workspace) || "ok"}`);
    await loadThreads();
  } catch (error) {
    messages.push({
      role: "system",
      title: "System",
      body: `Chat not opened. ${error.message}`,
      code: error.workspace ? `github: ${workspaceSummary(error.workspace)}` : "status: blocked",
      time: formatTime(),
    });
    renderTimeline();
    appendTerminal(`chat load error: ${error.message}`);
  }
}

async function startNewThread() {
  if (isSending) return;
  try {
    const response = await fetch("/api/thread/new", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: currentModel() }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not create chat.");
    messages = [
      {
        role: "system",
        title: "System",
        body: "New chat started.",
        time: formatTime(),
      },
    ];
    updateActiveThread(payload.thread || { title: "New chat" });
    renderTimeline();
    appendTerminal("new chat started");
    await loadThreads();
  } catch (error) {
    appendTerminal(`new chat error: ${error.message}`);
  }
}

function currentModel() {
  return modelSelect.value || bridgeConfig.model || DEFAULT_MODEL;
}

function setModelValue(model) {
  if (!model) return;
  const hasOption = Array.from(modelSelect.options).some((option) => option.value === model);
  if (!hasOption) {
    const option = document.createElement("option");
    option.value = model;
    option.textContent = model;
    modelSelect.prepend(option);
  }
  modelSelect.value = model;
  activeModel.textContent = model;
}

function errorMessage(error) {
  if (!error) return "Unknown error.";
  if (typeof error === "string") return error;
  if (error.message) return error.message;
  try {
    return JSON.stringify(error);
  } catch (_error) {
    return "Unknown error.";
  }
}

class CodexBridge {
  constructor(config) {
    this.updateConfig(config);
    this.ws = null;
    this.threadId = null;
    this.nextId = 1;
    this.pending = new Map();
    this.activeTurn = null;
  }

  updateConfig(config) {
    this.config = { ...(this.config || {}), ...config };
  }

  async connect() {
    if (!this.config.codexWebSocket) {
      throw new Error("Codex websocket is not available.");
    }

    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      await this.openSocket();
      await this.request(
        "initialize",
        {
          clientInfo: {
            name: "custom-ui",
            title: "Custom UI",
            version: "0.1.0",
          },
          capabilities: {
            experimentalApi: true,
            requestAttestation: false,
            optOutNotificationMethods: [],
          },
        },
        15000,
      );
    }

    if (!this.threadId) {
      await this.startThread();
    }
  }

  openSocket() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.config.codexWebSocket);
      const timer = window.setTimeout(() => {
        ws.close();
        reject(new Error("Timed out connecting to Codex."));
      }, 10000);

      ws.addEventListener("open", () => {
        window.clearTimeout(timer);
        this.ws = ws;
        resolve();
      });

      ws.addEventListener("message", (event) => this.handleMessage(event));
      ws.addEventListener("close", () => this.handleClose());
      ws.addEventListener("error", () => {
        window.clearTimeout(timer);
        reject(new Error("Codex websocket failed to connect."));
      });
    });
  }

  handleClose() {
    this.ws = null;
    this.threadId = null;
    this.rejectPending(new Error("Codex websocket closed."));
  }

  rejectPending(error) {
    this.pending.forEach((pending) => {
      window.clearTimeout(pending.timer);
      pending.reject(error);
    });
    this.pending.clear();

    if (this.activeTurn) {
      window.clearTimeout(this.activeTurn.timer);
      this.activeTurn.reject(error);
      this.activeTurn = null;
    }
  }

  request(method, params, timeoutMs = 30000) {
    const id = this.nextId;
    this.nextId += 1;

    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} timed out.`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });
      this.sendRaw({ id, method, params });
    });
  }

  sendRaw(message) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("Codex websocket is not open.");
    }
    this.ws.send(JSON.stringify(message));
  }

  handleMessage(event) {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch (_error) {
      return;
    }

    if (message.id && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      window.clearTimeout(pending.timer);
      if (message.error) {
        pending.reject(new Error(errorMessage(message.error)));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.id && this.activeTurn?.id === message.id && message.error) {
      this.finishTurn(new Error(errorMessage(message.error)));
      return;
    }

    if (message.method) {
      this.handleNotification(message);
    }
  }

  handleNotification(message) {
    const params = message.params || {};
    const turn = this.activeTurn;

    if (message.method === "item/agentMessage/delta" && turn) {
      turn.text += params.delta || "";
      turn.onDelta(turn.text);
      return;
    }

    if (message.method === "turn/started" && turn) {
      turn.onEvent("turn started");
      return;
    }

    if (message.method === "turn/plan/updated" && turn) {
      turn.onEvent("plan updated");
      return;
    }

    if (message.method === "turn/completed" && turn) {
      const status = params.turn?.status;
      if (status === "completed") {
        this.finishTurn(null, turn.text);
      } else {
        const detail = params.turn?.error ? errorMessage(params.turn.error) : `Turn ended with status ${status}.`;
        this.finishTurn(new Error(detail));
      }
      return;
    }

    if (message.method === "error" && turn) {
      this.finishTurn(new Error(errorMessage(params.error || params)));
    }
  }

  finishTurn(error, text = "") {
    if (!this.activeTurn) return;

    const turn = this.activeTurn;
    window.clearTimeout(turn.timer);
    this.activeTurn = null;

    if (error) {
      turn.reject(error);
    } else {
      turn.resolve(text);
    }
  }

  async startThread() {
    const cwd = this.config.cwd;
    const result = await this.request("thread/start", {
      cwd,
      runtimeWorkspaceRoots: cwd ? [cwd] : [],
      model: currentModel(),
      approvalPolicy: "never",
      sandbox: "workspace-write",
      sessionStartSource: "startup",
      threadSource: "user",
      experimentalRawEvents: false,
    });

    this.threadId = result?.thread?.id;
    if (!this.threadId) {
      throw new Error("Codex did not return a thread id.");
    }
  }

  async send(text, onDelta, onEvent) {
    await this.connect();

    if (this.activeTurn) {
      throw new Error("A Codex turn is already running.");
    }

    const id = this.nextId;
    this.nextId += 1;
    const cwd = this.config.cwd;

    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.finishTurn(new Error("Codex turn timed out."));
      }, 180000);

      this.activeTurn = {
        id,
        text: "",
        timer,
        resolve,
        reject,
        onDelta,
        onEvent,
      };

      try {
        this.sendRaw({
          id,
          method: "turn/start",
          params: {
            threadId: this.threadId,
            input: [{ type: "text", text, text_elements: [] }],
            cwd,
            runtimeWorkspaceRoots: cwd ? [cwd] : [],
            approvalPolicy: "never",
            model: currentModel(),
            sandboxPolicy: cwd
              ? {
                  type: "workspaceWrite",
                  writableRoots: [cwd],
                  networkAccess: true,
                  excludeTmpdirEnvVar: false,
                  excludeSlashTmp: false,
                }
              : null,
          },
        });
      } catch (error) {
        this.finishTurn(error);
      }
    });
  }
}

async function sendChat() {
  if (isSending) return;

  const task = chatInput.value.trim();
  if (!task) {
    chatInput.focus();
    return;
  }

  const selectedContexts = Array.from(document.querySelectorAll(".context-chip.is-active"))
    .map((chip) => chip.dataset.context)
    .join(", ");

  messages.push({
    role: "user",
    title: "You",
    body: task,
    time: formatTime(),
  });

  const pendingMessage = {
    role: "codex",
    title: "Codex",
    body: "Connecting to Codex...",
    code: `mode: ${activeView}\nmodel: ${currentModel()}\ncontext: ${selectedContexts || "none"}`,
    time: formatTime(),
    pending: true,
  };
  messages.push(pendingMessage);

  chatInput.value = "";
  renderTimeline();
  advancePlan();
  appendTerminal(`message sent: ${activeView}`);

  try {
    isSending = true;
    runButton.disabled = true;

    if (!bridgeConfig.connected) {
      await checkConnection();
    }

    pendingMessage.body = "Thinking...";
    pendingMessage.code = `mode: codex bridge\nmodel: ${currentModel()}\ncontext: ${selectedContexts || "none"}`;
    renderTimeline();

    const response = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: currentModel(),
        context: selectedContexts,
        threadId: activeThreadId,
        messages: chatPayload(),
      }),
    });
    const payload = await response.json();
    if (!response.ok) {
      const error = new Error(payload.error || "Chat request failed.");
      error.workspace = payload.workspace;
      throw error;
    }
    if (payload.threadId) {
      activeThreadId = payload.threadId;
      const active = threads.find((thread) => thread.id === activeThreadId);
      updateActiveThread(active || { id: activeThreadId, title: activeThreadName.textContent || "Selected chat" });
      loadThreads();
    }
    pendingMessage.body = payload.reply || "I did not receive a text response.";
    pendingMessage.code = [
      `mode: ${payload.mode || "local"}`,
      `model: ${currentModel()}`,
      `context: ${selectedContexts || "none"}`,
      `github: ${workspaceSummary(payload.workspace) || "not checked"}`,
    ].join("\n");
    appendTerminal(`reply received: ${payload.mode || "local"}`);
  } catch (error) {
    pendingMessage.body = `Codex stopped before running. ${error.message}`;
    pendingMessage.code = error.workspace
      ? `status: blocked\ngithub: ${workspaceSummary(error.workspace)}`
      : "status: bridge unavailable";
    appendTerminal(error.workspace ? "github snapshot blocked" : "chat bridge error");
  } finally {
    pendingMessage.pending = false;
    isSending = false;
    runButton.disabled = false;
    renderTimeline();
  }
}

function setView(view) {
  activeView = view;
  navItems.forEach((item) => item.classList.toggle("is-active", item.dataset.view === view));
  sessionMode.textContent = views[view].mode;
  viewTitle.textContent = views[view].title;
  chatInput.placeholder = views[view].prompt;
  appendTerminal(`view changed: ${view}`);
}

function setTheme(theme) {
  body.dataset.theme = theme;
  localStorage.setItem("codex-ui-theme", theme);
}

function toggleTheme() {
  setTheme(body.dataset.theme === "night" ? "day" : "night");
}

function setDensity(density) {
  body.dataset.density = density;
  localStorage.setItem("codex-ui-density", density);
  document.querySelectorAll("[data-density-choice]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.densityChoice === density);
  });
}

function openPalette() {
  palette.hidden = false;
  paletteInput.value = "";
  filterPalette("");
  requestAnimationFrame(() => paletteInput.focus());
}

function closePalette() {
  palette.hidden = true;
}

function filterPalette(query) {
  const normalized = query.trim().toLowerCase();
  Array.from(paletteList.children).forEach((button) => {
    button.hidden = normalized && !button.textContent.toLowerCase().includes(normalized);
  });
}

function runCommand(command) {
  const actions = {
    run: sendChat,
    theme: toggleTheme,
    focus: () => chatInput.focus(),
    clear: clearTimeline,
  };
  actions[command]?.();
  closePalette();
}

function clearTimeline() {
  messages = [
    {
      role: "system",
      title: "System",
      body: "Timeline cleared.",
      time: formatTime(),
    },
  ];
  renderTimeline();
  appendTerminal("timeline cleared");
}

function addFile() {
  const button = document.createElement("button");
  button.className = "file-row";
  button.type = "button";
  button.innerHTML = `<span>component-${fileIndex}.tsx</span><small>draft</small>`;
  fileIndex += 1;
  fileList.appendChild(button);
  appendTerminal("file context added");
}

navItems.forEach((item) => {
  item.addEventListener("click", () => setView(item.dataset.view));
});

document.querySelectorAll("[data-density-choice]").forEach((button) => {
  button.addEventListener("click", () => setDensity(button.dataset.densityChoice));
});

document.querySelectorAll(".context-chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    chip.classList.toggle("is-active");
    const active = Array.from(document.querySelectorAll(".context-chip.is-active"))
      .map((item) => item.dataset.context)
      .join(", ");
    appendTerminal(`context: ${active || "none"}`);
  });
});

fileList.addEventListener("click", (event) => {
  const row = event.target.closest(".file-row");
  if (!row) return;
  row.classList.toggle("is-selected");
});

threadList.addEventListener("click", (event) => {
  const row = event.target.closest(".thread-row[data-thread-id]");
  if (!row) return;
  selectThread(row.dataset.threadId);
});

planList.addEventListener("change", updatePlan);
runButton.addEventListener("click", sendChat);
chatForm.addEventListener("submit", (event) => {
  event.preventDefault();
  sendChat();
});
chatInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    sendChat();
  }
});
clearButton.addEventListener("click", clearTimeline);
themeToggle.addEventListener("click", toggleTheme);
paletteButton.addEventListener("click", openPalette);
addFileButton.addEventListener("click", addFile);
refreshThreadsButton.addEventListener("click", loadThreads);
newThreadButton.addEventListener("click", startNewThread);
projectButton.addEventListener("click", loadThreads);
modelSelect.addEventListener("change", () => {
  activeModel.textContent = currentModel();
});

palette.addEventListener("click", (event) => {
  if (event.target === palette) closePalette();
});

paletteInput.addEventListener("input", () => filterPalette(paletteInput.value));

paletteList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-command]");
  if (button) runCommand(button.dataset.command);
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closePalette();
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    openPalette();
  }
});

function tickClock() {
  localClock.textContent = formatTime();
}

async function checkConnection() {
  try {
    const response = await fetch("/api/status");
    if (!response.ok) throw new Error("status unavailable");
    const status = await response.json();
    bridgeConfig = {
      connected: status.mode === "codex" && Boolean(status.codexWebSocket),
      mode: status.mode || "local",
      model: status.model || currentModel(),
      codexWebSocket: status.codexWebSocket || null,
      cwd: status.cwd || null,
      error: status.bridge?.error || null,
    };
    if (codexBridge) codexBridge.updateConfig(bridgeConfig);
    if (status.activeThreadId) activeThreadId = status.activeThreadId;
    setModelValue(bridgeConfig.model);
    connectionStatus.textContent = bridgeConfig.connected ? "codex" : bridgeConfig.mode;
    serverMode.textContent = bridgeConfig.connected ? "codex bridge" : bridgeConfig.mode;
    connectionDot.style.background = bridgeConfig.connected ? "var(--green)" : "var(--gold)";
    messages = messages.map((message) =>
      message.role === "system"
        ? {
            ...message,
            body: bridgeConfig.connected
              ? "Codex app-server connected."
              : `Codex bridge is not ready${bridgeConfig.error ? `: ${bridgeConfig.error}` : "."}`,
          }
        : message,
    );
    renderTimeline();
    return bridgeConfig;
  } catch (_error) {
    bridgeConfig = {
      connected: false,
      mode: "static",
      model: currentModel(),
      codexWebSocket: null,
      cwd: null,
    };
    connectionStatus.textContent = "static";
    serverMode.textContent = "static";
    connectionDot.style.background = "var(--coral)";
    messages = messages.map((message) =>
      message.role === "system"
        ? { ...message, body: "The page is open, but the local chat server is not responding." }
        : message,
    );
  }
  renderTimeline();
  return bridgeConfig;
}

const savedTheme = localStorage.getItem("codex-ui-theme");
const savedDensity = localStorage.getItem("codex-ui-density");
if (savedTheme === "day" || savedTheme === "night") setTheme(savedTheme);
if (savedDensity === "compact" || savedDensity === "comfortable") setDensity(savedDensity);

tickClock();
setInterval(tickClock, 30000);
updatePlan();
renderTimeline();
checkConnection().then(() => loadThreads());
