const DEFAULT_BROWSER_CLIENT = "file:///C:/Users/zev/.codex/plugins/cache/openai-bundled/chrome/26.608.12217/scripts/browser-client.mjs";

function nowStamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
}

function safeName(value) {
  const cleaned = String(value || "General").replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return cleaned || "General";
}

function normalizeTaskText(value) {
  return String(value || "").replace(/\s+/g, " ").trim().toLowerCase();
}

async function taskKeyFor(project, task) {
  const crypto = await import("node:crypto");
  return crypto
    .createHash("sha256")
    .update(`${normalizeTaskText(project || "Gateway")}\n${normalizeTaskText(task)}`, "utf8")
    .digest("hex");
}

function extFromContentType(contentType) {
  if (!contentType) return ".bin";
  if (contentType.includes("png")) return ".png";
  if (contentType.includes("jpeg") || contentType.includes("jpg")) return ".jpg";
  if (contentType.includes("webp")) return ".webp";
  if (contentType.includes("svg")) return ".svg";
  return ".bin";
}

function isLikelyGeneratedImage(asset) {
  const url = asset?.url || "";
  return /backend-api\/estuary\/content|files\.oaiusercontent|oaidalle|dalle|generated/i.test(url);
}

function shouldRequireTextResponse(options, project, task, prompt) {
  if (options.requireTextResponse === true) return true;
  if (options.requireTextResponse === false) return false;
  const haystack = `${project || ""}\n${task || ""}\n${prompt || ""}`;
  return /writer|editor|content|article|seo|recommended_publish_status|task_type|CODEX_RETURN_PACKET/i.test(haystack);
}

async function assistantMessageCount(tab) {
  try {
    return await tab.playwright.locator("[data-message-author-role=\"assistant\"]").count();
  } catch {
    return 0;
  }
}

async function waitForSettled(tab, maxWaitMs = 180000, minAssistantCount = 0) {
  const start = Date.now();
  let lastSnapshot = "";
  let stableCount = 0;
  let lastBusy = false;

  while (Date.now() - start < maxWaitMs) {
    lastSnapshot = await tab.playwright.domSnapshot();
    const busy = /Stop answering|Generating image|Creating image|Reading documents?|Reading files?|Pro thinking|Thinking|Analyzing|Working/i.test(lastSnapshot);
    const assistantCount = await assistantMessageCount(tab);
    const hasResult = /Response actions|Copy response|Generated image/i.test(lastSnapshot)
      || (minAssistantCount > 0 && assistantCount >= minAssistantCount)
      || (minAssistantCount <= 0 && assistantCount > 0);
    lastBusy = busy;

    if (!busy && hasResult) {
      stableCount += 1;
      if (stableCount >= 2) return { snapshot: lastSnapshot, timedOut: false, busy: false };
    } else {
      stableCount = 0;
    }

    await tab.playwright.waitForTimeout(2500);
  }

  return { snapshot: lastSnapshot, timedOut: true, busy: lastBusy };
}

async function waitForNewAssistant(tab, previousCount, maxWaitMs = 60000) {
  return await waitForSettled(tab, maxWaitMs, previousCount + 1);
}

async function submitChatGptPrompt(tab, textbox) {
  const selectorButtons = [
    "button[aria-label=\"Send prompt\"]",
    "button[aria-label=\"Send message\"]",
    "[data-testid=\"send-button\"]",
  ];
  const tried = [];

  for (const selector of selectorButtons) {
    const buttons = tab.playwright.locator(selector);
    const count = await buttons.count();
    tried.push(`${selector}:${count}`);
    for (let index = count - 1; index >= 0; index -= 1) {
      try {
        await buttons.nth(index).click({ timeoutMs: 10000, force: true });
        await tab.playwright.waitForTimeout(800);
        return { method: `selector:${selector}`, tried };
      } catch {
        // Keep looking for a clickable send control before falling back to role/Enter.
      }
    }
  }

  const buttonLabels = ["Send prompt", "Send message"];
  for (const label of buttonLabels) {
    const buttons = tab.playwright.getByRole("button", { name: label });
    const count = await buttons.count();
    tried.push(`${label}:${count}`);
    for (let index = count - 1; index >= 0; index -= 1) {
      try {
        await buttons.nth(index).click({ timeoutMs: 10000 });
        await tab.playwright.waitForTimeout(800);
        return { method: `button:${label}`, tried };
      } catch {
        // Keep looking for a clickable send control before falling back to Enter.
      }
    }
  }

  await textbox.press("Enter", { timeoutMs: 15000 });
  await tab.playwright.waitForTimeout(800);
  return { method: "keyboard:enter", tried };
}

async function readTextboxText(textbox) {
  try {
    return await textbox.innerText({ timeoutMs: 3000 });
  } catch {
    try {
      return await textbox.inputValue({ timeoutMs: 3000 });
    } catch {
      return "";
    }
  }
}

async function ensureAttachedPromptHasInstruction(tab, textbox, project) {
  await tab.playwright.waitForTimeout(1200);
  const textboxText = await readTextboxText(textbox);
  if (String(textboxText || "").trim()) {
    return { mode: "direct_text", instruction: "" };
  }

  const bodyText = await readBodyText(tab);
  const hasTextAttachment = /Show in text field|Remove file|Pasted text/i.test(bodyText);
  if (!hasTextAttachment) {
    return { mode: "empty_textbox", instruction: "" };
  }

  const instruction = `Please process the attached ${project} prompt exactly. Return only the requested CODEX_RETURN_PACKET.`;
  await textbox.fill(instruction, { timeoutMs: 15000 });
  await tab.playwright.waitForTimeout(800);
  return { mode: "attachment_plus_instruction", instruction };
}

function splitPromptChunks(prompt, maxChars = 6200) {
  const chunks = [];
  let current = "";
  const paragraphs = String(prompt || "").split(/\n{2,}/);

  for (const paragraph of paragraphs) {
    const next = current ? `${current}\n\n${paragraph}` : paragraph;
    if (next.length <= maxChars) {
      current = next;
      continue;
    }
    if (current) chunks.push(current);
    current = paragraph;
    while (current.length > maxChars) {
      chunks.push(current.slice(0, maxChars));
      current = current.slice(maxChars);
    }
  }

  if (current.trim()) chunks.push(current);
  return chunks.length > 0 ? chunks : [String(prompt || "")];
}

async function submitTextMessage(tab, textbox, text, project, { allowAttachmentInstruction = true } = {}) {
  let fillError = "";
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      await textbox.fill(text, { timeoutMs: 20000 });
      fillError = "";
      break;
    } catch (error) {
      fillError = String(error?.message || error);
      await tab.playwright.waitForTimeout(1500);
    }
  }
  if (fillError) {
    throw new Error(`ChatGPT composer fill failed after retries: ${fillError}`);
  }
  let promptMode = "direct_text";
  let attachmentInstruction = "";

  if (allowAttachmentInstruction) {
    let attachmentResult = await ensureAttachedPromptHasInstruction(tab, textbox, project);
    if (attachmentResult.mode === "empty_textbox") {
      try {
        await tab.clipboard.writeText(text);
        await textbox.click({ timeoutMs: 10000 });
        await tab.cua.keypress({ keys: ["CTRL", "V"] });
        await tab.playwright.waitForTimeout(1000);
        attachmentResult = await ensureAttachedPromptHasInstruction(tab, textbox, project);
      } catch {
        // The explicit empty-composer check below turns this into a useful failure.
      }
    }
    if (attachmentResult.mode === "empty_textbox") {
      throw new Error("ChatGPT composer stayed empty after fill and clipboard-paste fallback.");
    }
    promptMode = attachmentResult.mode;
    attachmentInstruction = attachmentResult.instruction;
  } else {
    await tab.playwright.waitForTimeout(600);
    const textboxText = await readTextboxText(textbox);
    if (!String(textboxText || "").trim()) {
      throw new Error("ChatGPT converted a chunk into an attachment. Reduce chunkCharLimit and retry.");
    }
  }

  const submitResult = await submitChatGptPrompt(tab, textbox);
  return {
    promptMode,
    attachmentInstruction,
    submitMethod: submitResult.method,
    submitTried: submitResult.tried,
  };
}

async function submitPromptWorkflow(tab, textbox, prompt, project, options = {}) {
  const directCharLimit = Number(options.directCharLimit || 11000);
  const chunkCharLimit = Number(options.chunkCharLimit || 6200);
  const chunkAckWaitMs = Number(options.chunkAckWaitMs || 25000);
  const promptText = String(prompt || "");
  const onProgress = typeof options.onProgress === "function" ? options.onProgress : async () => {};

  if (promptText.length <= directCharLimit || options.chunkLongPrompt === false) {
    const previousAssistantCount = await assistantMessageCount(tab);
    await onProgress({
      Status: "submitting_prompt",
      PromptSubmitMode: "direct_or_attachment",
      PromptChunks: 1,
      CurrentPromptChunk: 1,
      ExpectedAssistantCount: previousAssistantCount + 1,
    });
    const submitResult = await submitTextMessage(tab, textbox, promptText, project, {
      allowAttachmentInstruction: true,
    });
    return {
      ...submitResult,
      promptMode: submitResult.promptMode,
      chunks: 1,
      expectedAssistantCount: previousAssistantCount + 1,
    };
  }

  const chunks = splitPromptChunks(promptText, chunkCharLimit);
  let lastSubmitResult = {};
  await onProgress({
    Status: "submitting_prompt_chunks",
    PromptSubmitMode: "chunked_text",
    PromptChunks: chunks.length,
    CurrentPromptChunk: 0,
  });
  for (let index = 0; index < chunks.length; index += 1) {
    const chunkNumber = index + 1;
    const finalChunk = chunkNumber === chunks.length;
    const previousAssistantCount = await assistantMessageCount(tab);
    const message = finalChunk
      ? [
          `FINAL PART ${chunkNumber}/${chunks.length}`,
          "",
          chunks[index],
          "",
          `Now use all ${chunks.length} parts above as one complete ${project} prompt. Execute the full assignment and return the requested final output plus CODEX_RETURN_PACKET.`,
        ].join("\n")
      : [
          `PART ${chunkNumber}/${chunks.length}`,
          "",
          chunks[index],
          "",
          `Do not execute the assignment yet. Store this part as context and reply only: ACK ${chunkNumber}/${chunks.length}.`,
        ].join("\n");

    await onProgress({
      Status: finalChunk ? "submitting_final_chunk" : "submitting_context_chunk",
      PromptSubmitMode: "chunked_text",
      PromptChunks: chunks.length,
      CurrentPromptChunk: chunkNumber,
      ExpectedAssistantCount: previousAssistantCount + 1,
    });
    lastSubmitResult = await submitTextMessage(tab, textbox, message, project, {
      allowAttachmentInstruction: false,
    });
    await onProgress({
      Status: finalChunk ? "submitted_final_chunk" : "submitted_context_chunk",
      PromptSubmitMode: "chunked_text",
      PromptChunks: chunks.length,
      CurrentPromptChunk: chunkNumber,
      SubmitMethod: lastSubmitResult.submitMethod,
      SubmitTried: lastSubmitResult.submitTried,
      ExpectedAssistantCount: previousAssistantCount + 1,
    });

    if (!finalChunk) {
      await waitForNewAssistant(tab, previousAssistantCount, chunkAckWaitMs);
      await onProgress({
        Status: "context_chunk_acknowledged",
        PromptSubmitMode: "chunked_text",
        PromptChunks: chunks.length,
        CurrentPromptChunk: chunkNumber,
      });
      continue;
    }

    return {
      ...lastSubmitResult,
      promptMode: "chunked_text",
      chunks: chunks.length,
      expectedAssistantCount: previousAssistantCount + 1,
    };
  }

  throw new Error("Prompt chunk submission failed before final chunk.");
}

function cleanPacketText(value) {
  return String(value || "")
    .replace(/^\s*-\s*/gm, "")
    .replace(/\n\s+-\s+/g, "\n")
    .trim();
}

function isPromptEcho(value, prompt) {
  const normalizedValue = normalizeTaskText(value);
  const normalizedPrompt = normalizeTaskText(prompt);
  if (!normalizedValue || !normalizedPrompt) return false;

  const lead = normalizedPrompt.slice(0, Math.min(220, normalizedPrompt.length));
  if (lead.length >= 80 && normalizedValue.includes(lead)) return true;

  const fingerprint = normalizedValue.slice(0, Math.min(650, normalizedValue.length));
  return fingerprint.length >= 120 && normalizedPrompt.includes(fingerprint);
}

function extractLastReturnPacket(value, prompt = "") {
  const packetRegex = /CODEX_RETURN_PACKET[\s\S]*?END_CODEX_RETURN_PACKET/gi;
  let match;
  let lastPacket = "";
  while ((match = packetRegex.exec(String(value || ""))) !== null) {
    const candidate = cleanPacketText(match[0]);
    if (isPromptEcho(candidate, prompt)) continue;
    lastPacket = candidate;
  }
  return lastPacket;
}

async function readLatestAssistantText(tab, prompt = "") {
  const selectors = [
    "[data-message-author-role=\"assistant\"]",
    "article",
  ];
  let fallbackText = "";

  for (const selector of selectors) {
    const messages = tab.playwright.locator(selector);
    const count = await messages.count();
    for (let index = count - 1; index >= 0; index -= 1) {
      let text = "";
      try {
        text = await messages.nth(index).innerText({ timeoutMs: 5000 });
      } catch {
        continue;
      }
      const cleaned = String(text || "").trim();
      if (!cleaned || isPromptEcho(cleaned, prompt)) continue;
      if (!fallbackText) fallbackText = cleaned;
      if (/CODEX_RETURN_PACKET/i.test(cleaned)) return cleaned;
    }
  }

  return fallbackText;
}

async function readBodyText(tab) {
  try {
    return await tab.playwright.locator("body").innerText({ timeoutMs: 10000 });
  } catch {
    return "";
  }
}

async function findChatGptComposer(tab, maxWaitMs = 45000) {
  const start = Date.now();
  let lastError = "";

  while (Date.now() - start < maxWaitMs) {
    const candidates = [
      () => tab.playwright.getByRole("textbox", { name: "Chat with ChatGPT" }),
      () => tab.playwright.getByPlaceholder("Ask anything", { exact: true }),
      () => tab.playwright.locator("[contenteditable=\"true\"][role=\"textbox\"]"),
      () => tab.playwright.locator("textarea"),
    ];

    for (const makeCandidate of candidates) {
      const candidate = makeCandidate();
      try {
        const count = await candidate.count();
        if (count === 1) return { textbox: candidate, count };
        if (count > 1) return { textbox: candidate.nth(count - 1), count };
      } catch (error) {
        lastError = String(error?.message || error);
      }
    }

    await tab.playwright.waitForTimeout(1500);
  }

  const bodyText = await readBodyText(tab);
  throw new Error(
    `ChatGPT composer not ready or login required. Last selector error: ${lastError}. Body excerpt: ${bodyText.slice(0, 500)}`,
  );
}

async function gotoChatGpt(tab, fs, sessionPath, responsePath, outputDir) {
  try {
    await tab.goto("https://chatgpt.com/", { timeoutMs: 20000 });
  } catch (error) {
    await writeSession(fs, sessionPath, {
      Status: "chatgpt_goto_timeout",
      GotoTimeoutAt: new Date().toISOString(),
      GotoError: String(error?.message || error).slice(0, 300),
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
  }
}

async function readPrompt(fs, options) {
  if (options.prompt) return String(options.prompt);
  if (options.promptPath) return await fs.readFile(options.promptPath, "utf8");
  throw new Error("runChatGptChromeBridge requires prompt or promptPath.");
}

async function appendJsonLine(fs, path, value) {
  await fs.mkdir(path.substring(0, path.lastIndexOf("/")), { recursive: true });
  await fs.appendFile(path, `${JSON.stringify(value)}\n`, "utf8");
}

async function writeSession(fs, sessionPath, patch) {
  if (!sessionPath) return;
  let session = {};
  try {
    session = JSON.parse(await fs.readFile(sessionPath, "utf8"));
  } catch {
    session = {};
  }
  Object.assign(session, patch);
  await fs.writeFile(sessionPath, JSON.stringify(session, null, 2), "utf8");
}

async function readSession(fs, sessionPath) {
  if (!sessionPath) return {};
  try {
    return JSON.parse(await fs.readFile(sessionPath, "utf8"));
  } catch {
    return {};
  }
}

async function openChromeProfileWindow(browserClientPath) {
  const childProcess = await import("node:child_process");
  const { fileURLToPath } = await import("node:url");
  const path = await import("node:path");
  const scriptPath = path.join(path.dirname(fileURLToPath(browserClientPath)), "open-chrome-window.js");

  await new Promise((resolve) => {
    childProcess.execFile("node", [scriptPath], { windowsHide: true }, () => resolve());
  });
}

async function getExtensionBrowserWithRetry(setupBrowserRuntime, browserClientPath) {
  await setupBrowserRuntime({ globals: globalThis });
  try {
    return await agent.browsers.get("extension");
  } catch (firstError) {
    if (!/not available|extension/i.test(String(firstError?.message || firstError))) {
      throw firstError;
    }
    await openChromeProfileWindow(browserClientPath);
    await new Promise((resolve) => setTimeout(resolve, 2500));
    await setupBrowserRuntime({ globals: globalThis });
    return await agent.browsers.get("extension");
  }
}

export async function runChatGptChromeBridge(options = {}) {
  const fs = await import("node:fs/promises");
  const path = await import("node:path");
  const browserClientPath = options.browserClientPath || DEFAULT_BROWSER_CLIENT;
  const { setupBrowserRuntime } = await import(browserClientPath);

  const project = options.project || "General";
  const sessionId = options.sessionId || nowStamp();
  const codexHome = "C:/Users/zev/.codex";
  const outputDir = options.outputDir || `${codexHome}/generated_assets/chatgpt-bridge/${safeName(project)}`;
  const responsePath = options.responsePath || `${codexHome}/logs/chatgpt-bridge/${sessionId}-${safeName(project)}/response.txt`;
  const handoffDir = `${codexHome}/handoffs/chatgpt`;
  const handoffPath = `${handoffDir}/${sessionId}-${safeName(project)}.txt`;
  const eventsPath = `${codexHome}/logs/chatgpt-bridge/events.jsonl`;

  await fs.mkdir(outputDir, { recursive: true });
  await fs.mkdir(path.dirname(responsePath), { recursive: true });
  await fs.mkdir(handoffDir, { recursive: true });

  const prompt = await readPrompt(fs, options);
  const startingSession = await readSession(fs, options.sessionPath);
  const task = options.task || startingSession.Task || "";
  const taskKey = task ? await taskKeyFor(project, task) : "";
  const requireTextResponse = shouldRequireTextResponse(options, project, task, prompt);
  const shouldSubmit = options.submitPrompt !== false;

  await writeSession(fs, options.sessionPath, {
    Status: shouldSubmit ? "opening_chatgpt" : "opening_chatgpt_for_harvest",
    OpenStartedAt: new Date().toISOString(),
    ResponsePath: responsePath,
    AssetOutDir: outputDir,
  });

  const browser = await getExtensionBrowserWithRetry(setupBrowserRuntime, browserClientPath);
  await browser.nameSession?.("chatgpt-bridge");

  let tab;
  const useFreshTab = shouldSubmit && options.newChat !== false && options.freshTab !== false;
  if (useFreshTab) {
    tab = await browser.tabs.new();
    await gotoChatGpt(tab, fs, options.sessionPath, responsePath, outputDir);
  } else {
    const openTabs = await browser.user.openTabs();
    const chatgptTabs = openTabs.filter((candidate) => /chatgpt\.com/i.test(candidate.url || candidate.title || ""));
    const preferredChatUrl = String(startingSession.WaitingUrl || startingSession.ChatUrl || startingSession.SubmittedUrl || "");
    const exactChatTab = preferredChatUrl && /chatgpt\.com\/c\//i.test(preferredChatUrl)
      ? chatgptTabs.find((candidate) => candidate.url === preferredChatUrl)
      : null;
    const chatgptTab = exactChatTab || (chatgptTabs.length > 0 ? chatgptTabs[chatgptTabs.length - 1] : null);
    if (chatgptTab) {
      tab = await browser.user.claimTab(chatgptTab);
    } else {
      tab = await browser.tabs.new();
      await gotoChatGpt(tab, fs, options.sessionPath, responsePath, outputDir);
    }
  }

  const currentUrl = await tab.url();
  if (!/chatgpt\.com/i.test(currentUrl || "")) {
    await gotoChatGpt(tab, fs, options.sessionPath, responsePath, outputDir);
  }
  try {
    await tab.playwright.waitForLoadState({ state: "domcontentloaded", timeoutMs: 20000 });
  } catch (error) {
    await writeSession(fs, options.sessionPath, {
      Status: "chatgpt_load_state_timeout",
      LoadStateTimeoutAt: new Date().toISOString(),
      LoadStateError: String(error?.message || error).slice(0, 300),
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
  }

  if (shouldSubmit && options.newChat !== false && !useFreshTab) {
    await tab.cua.keypress({ keys: ["CTRL", "SHIFT", "O"] });
    await tab.playwright.waitForTimeout(1200);
  }

  let snapshot = "";
  if (shouldSubmit) {
    await writeSession(fs, options.sessionPath, {
      Status: "waiting_for_composer",
      ComposerWaitStartedAt: new Date().toISOString(),
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
    const { textbox, count: textboxCount } = await findChatGptComposer(tab, Number(options.composerWaitMs || 45000));

    await writeSession(fs, options.sessionPath, {
      Status: "submitting",
      SubmitStartedAt: new Date().toISOString(),
      TextboxCount: textboxCount,
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
    const promptSubmitResult = await submitPromptWorkflow(tab, textbox, prompt, project, {
      ...options,
      onProgress: async (patch) => {
        await writeSession(fs, options.sessionPath, {
          ...patch,
          UpdatedAt: new Date().toISOString(),
          ResponsePath: responsePath,
          AssetOutDir: outputDir,
        });
      },
    });
    const submittedUrl = await tab.url();
    await writeSession(fs, options.sessionPath, {
      Status: "submitted",
      SubmittedAt: new Date().toISOString(),
      SubmittedUrl: submittedUrl,
      SubmitMethod: promptSubmitResult.submitMethod,
      SubmitTried: promptSubmitResult.submitTried,
      PromptSubmitMode: promptSubmitResult.promptMode,
      AttachmentInstruction: promptSubmitResult.attachmentInstruction,
      PromptChunks: promptSubmitResult.chunks,
      ExpectedAssistantCount: promptSubmitResult.expectedAssistantCount,
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
  }

  const submittedSession = await readSession(fs, options.sessionPath);
  const waitResult = await waitForSettled(
    tab,
    options.maxWaitMs || 95000,
    Number(submittedSession.ExpectedAssistantCount || 0),
  );
  snapshot = waitResult.snapshot;
  if (waitResult.timedOut && waitResult.busy) {
    const waitingUrl = await tab.url();
    const waitingResult = {
      status: "waiting",
      project,
      promptPath: options.promptPath || "",
      responsePath,
      handoffPath: "",
      outputDir,
      assets: [],
      hasPacket: false,
      sessionPath: options.sessionPath || "",
      note: "ChatGPT was still generating when the Codex tool timeout guard was reached. Re-run with submitPrompt:false to harvest the completed response.",
    };
    await writeSession(fs, options.sessionPath, {
      Status: "waiting",
      WaitingAt: new Date().toISOString(),
      WaitingUrl: waitingUrl,
      ChatUrl: /chatgpt\.com\/c\//i.test(waitingUrl || "") ? waitingUrl : startingSession.ChatUrl || "",
      ResumeHint: "Run chatgpt-chrome-bridge.mjs again with submitPrompt:false and newChat:false.",
    });
    await appendJsonLine(fs, eventsPath, {
      type: "waiting",
      at: new Date().toISOString(),
      project,
      task,
      taskKey,
      responsePath,
      outputDir,
      avoidedCodexCreativeWork: true,
    });
    if (options.finalize !== false) {
      await browser.tabs.finalize({ keep: [{ tab, status: "handoff" }] });
    }
    return waitingResult;
  }

  let responseText = "";
  const copyButtons = tab.playwright.getByRole("button", { name: "Copy response" });
  const copyCount = await copyButtons.count();
  if (copyCount > 0) {
    await copyButtons.nth(copyCount - 1).click({ timeoutMs: 10000 });
    await tab.playwright.waitForTimeout(700);
    responseText = await tab.clipboard.readText();
  }

  if (!responseText.trim() || (requireTextResponse && !extractLastReturnPacket(responseText, prompt))) {
    const assistantText = await readLatestAssistantText(tab, prompt);
    const assistantPacket = extractLastReturnPacket(assistantText, prompt);
    if (assistantPacket) {
      responseText = assistantPacket;
    } else if (!responseText.trim() && assistantText.trim()) {
      responseText = assistantText.trim();
    }
  }

  if (!responseText.trim()) {
    const bodyPacket = extractLastReturnPacket(await readBodyText(tab), prompt);
    if (bodyPacket) responseText = bodyPacket;
  }

  if (!responseText.trim()) {
    const snapshotPacket = extractLastReturnPacket(snapshot, prompt);
    if (snapshotPacket) responseText = snapshotPacket;
  }

  if (!/CODEX_RETURN_PACKET/i.test(responseText) && requireTextResponse) {
    const failureText = [
      "CHATGPT_BRIDGE_HARVEST_FAILED",
      "",
      `Project: ${project}`,
      `Task: ${task || "unknown"}`,
      `Prompt path: ${options.promptPath || ""}`,
      `Response path: ${responsePath}`,
      "",
      "Reason: ChatGPT appeared reachable, but the bridge could not capture a text CODEX_RETURN_PACKET.",
      "This text-route run was not converted into a synthetic image packet, because that would create a false content import.",
      "",
      "Next action: Re-run resumeChatGptChromeBridge after the ChatGPT answer is visible, or manually copy the real CODEX_RETURN_PACKET.",
      "",
    ].join("\n");
    await fs.writeFile(responsePath, failureText, "utf8");
    await fs.writeFile(handoffPath, failureText, "utf8");
    await writeSession(fs, options.sessionPath, {
      Status: "harvest_failed_no_text",
      FailedAt: new Date().toISOString(),
      TaskKey: taskKey,
      ResponsePath: responsePath,
      HandoffPath: handoffPath,
      HasPacket: false,
      FailureReason: "Text-route bridge could not capture a CODEX_RETURN_PACKET.",
    });
    await appendJsonLine(fs, eventsPath, {
      type: "harvest_failed_no_text",
      at: new Date().toISOString(),
      project,
      task,
      taskKey,
      responsePath,
      handoffPath,
      avoidedCodexCreativeWork: true,
    });
    if (options.finalize !== false) {
      await browser.tabs.finalize({ keep: [{ tab, status: "handoff" }] });
    }
    return {
      status: "harvest_failed_no_text",
      project,
      task,
      taskKey,
      promptPath: options.promptPath || "",
      responsePath,
      handoffPath,
      outputDir,
      assets: [],
      hasPacket: false,
      sessionPath: options.sessionPath || "",
    };
  }

  const pageAssets = await tab.capabilities.get("pageAssets");
  const inventory = await pageAssets.list();
  const imageCandidates = inventory.assets.filter((asset) => asset.kind === "image");
  const generatedImages = imageCandidates.filter(isLikelyGeneratedImage);
  const selectedImages = generatedImages.length > 0 ? generatedImages : imageCandidates.slice(-4);
  let copiedAssets = [];
  let bundled = null;

  if (selectedImages.length > 0) {
    bundled = await pageAssets.bundle({
      inventoryId: inventory.id,
      assetIds: selectedImages.map((asset) => asset.id),
    });

    let index = 1;
    for (const asset of bundled.assets) {
      const ext = extFromContentType(asset.contentType);
      const destination = path.join(outputDir, `chatgpt-${sessionId}-${String(index).padStart(2, "0")}${ext}`);
      await fs.copyFile(asset.path, destination);
      copiedAssets.push({
        source: asset.path,
        path: destination,
        contentType: asset.contentType,
        url: asset.url,
      });
      index += 1;
    }
  }

  if (!/CODEX_RETURN_PACKET/i.test(responseText)) {
    const assetList = copiedAssets.length > 0
      ? copiedAssets.map((asset) => asset.path).join("\n")
      : "none";
    const syntheticPacket = `CODEX_RETURN_PACKET
Summary:
ChatGPT bridge automation completed. ${copiedAssets.length} image asset(s) were bundled from the ChatGPT page.
Decisions:
Used ChatGPT for detachable creative work and Codex Desktop only for browser automation, asset download, and local saving.
Deliverable:
${responseText.trim() || "ChatGPT returned generated image asset(s) without a separate text response."}
Codex next action:
Inspect and use the downloaded asset(s) locally.
Files/assets needed:
${assetList}
Owner buttons needed:
none
Confidence:
medium
Go back to Codex?:
yes
END_CODEX_RETURN_PACKET`;
    responseText = responseText.trim() ? `${responseText.trim()}\n\n${syntheticPacket}` : syntheticPacket;
  }

  await fs.writeFile(responsePath, responseText, "utf8");
  await fs.writeFile(handoffPath, responseText, "utf8");

  const result = {
    status: "complete",
    project,
    task,
    taskKey,
    promptPath: options.promptPath || "",
    responsePath,
    handoffPath,
    outputDir,
    assets: copiedAssets,
    imageInventoryCount: imageCandidates.length,
    generatedImageCount: generatedImages.length,
    hasPacket: /CODEX_RETURN_PACKET/i.test(responseText),
    sessionPath: options.sessionPath || "",
  };

  await writeSession(fs, options.sessionPath, {
    Status: "complete",
    CompletedAt: new Date().toISOString(),
    TaskKey: taskKey,
    ResponsePath: responsePath,
    HandoffPath: handoffPath,
    Assets: copiedAssets,
    ChatUrl: await tab.url(),
    HasPacket: result.hasPacket,
  });

  let cachePath = "";
  if (task && taskKey) {
    const cacheDir = `${codexHome}/cache/chatgpt-bridge`;
    cachePath = `${cacheDir}/${taskKey}.json`;
    const completedAt = new Date().toISOString();
    const cacheEntry = {
      version: 1,
      taskKey,
      project,
      task,
      route: startingSession?.Route?.Route || "chatgpt",
      confidence: startingSession?.Route?.Confidence || "",
      signals: startingSession?.Route?.Signals || [],
      completedAt,
      promptPath: options.promptPath || "",
      responsePath,
      handoffPath,
      outputDir,
      assets: copiedAssets,
      assetCount: copiedAssets.length,
      imageInventoryCount: imageCandidates.length,
      generatedImageCount: generatedImages.length,
      hasPacket: result.hasPacket,
      sourceSessionPath: options.sessionPath || "",
      savingsEstimate: startingSession?.SavingsEstimate || null,
      feedback: [],
    };
    await fs.mkdir(cacheDir, { recursive: true });
    await fs.writeFile(cachePath, JSON.stringify(cacheEntry, null, 2), "utf8");
    await writeSession(fs, options.sessionPath, {
      CachePath: cachePath,
      CacheStatus: "stored",
    });
    result.cachePath = cachePath;
  }

  await appendJsonLine(fs, eventsPath, {
    type: "complete",
    at: new Date().toISOString(),
    project,
    task,
    taskKey,
    responsePath,
    handoffPath,
    outputDir,
    assetCount: copiedAssets.length,
    hasPacket: result.hasPacket,
    cachePath,
    avoidedCodexCreativeWork: true,
  });

  if (options.finalize !== false) {
    await browser.tabs.finalize({ keep: [{ tab, status: "handoff" }] });
  }

  return result;
}

export async function resumeChatGptChromeBridge(options = {}) {
  return await runChatGptChromeBridge({
    ...options,
    submitPrompt: false,
    newChat: false,
  });
}
