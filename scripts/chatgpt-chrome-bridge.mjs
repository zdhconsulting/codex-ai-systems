const DEFAULT_BROWSER_CLIENT = "file:///C:/Users/zev/.codex/plugins/cache/openai-bundled/chrome/26.608.12217/scripts/browser-client.mjs";

function nowStamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
}

function safeName(value) {
  const cleaned = String(value || "General").replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return cleaned || "General";
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

async function waitForSettled(tab, maxWaitMs = 180000) {
  const start = Date.now();
  let lastSnapshot = "";
  let stableCount = 0;
  let lastBusy = false;

  while (Date.now() - start < maxWaitMs) {
    lastSnapshot = await tab.playwright.domSnapshot();
    const busy = /Stop answering|Generating image|Creating image/i.test(lastSnapshot);
    const hasResult = /Response actions|Copy response|Generated image|CODEX_RETURN_PACKET/i.test(lastSnapshot);
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

export async function runChatGptChromeBridge(options = {}) {
  const fs = await import("node:fs/promises");
  const path = await import("node:path");
  const browserClientPath = options.browserClientPath || DEFAULT_BROWSER_CLIENT;
  const { setupBrowserRuntime } = await import(browserClientPath);

  await setupBrowserRuntime({ globals: globalThis });
  const browser = await agent.browsers.get("extension");
  await browser.nameSession?.("chatgpt-bridge");

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

  let tab;
  const openTabs = await browser.user.openTabs();
  const chatgptTab = openTabs.find((candidate) => /chatgpt\.com/i.test(candidate.url || candidate.title || ""));
  if (chatgptTab) {
    tab = await browser.user.claimTab(chatgptTab);
  } else {
    tab = await browser.tabs.new();
    await tab.goto("https://chatgpt.com/");
  }

  const currentUrl = await tab.url();
  if (!/chatgpt\.com/i.test(currentUrl || "")) {
    await tab.goto("https://chatgpt.com/");
  }
  await tab.playwright.waitForLoadState({ state: "domcontentloaded", timeoutMs: 15000 });

  const shouldSubmit = options.submitPrompt !== false;

  if (shouldSubmit && options.newChat !== false) {
    await tab.cua.keypress({ keys: ["CTRL", "SHIFT", "O"] });
    await tab.playwright.waitForTimeout(1200);
  }

  let snapshot = await tab.playwright.domSnapshot();
  if (shouldSubmit) {
    let textbox = tab.playwright.getByRole("textbox", { name: "Chat with ChatGPT" });
    let textboxCount = await textbox.count();
    if (textboxCount !== 1) {
      textbox = tab.playwright.getByPlaceholder("Ask anything", { exact: true });
      textboxCount = await textbox.count();
    }
    if (textboxCount !== 1) {
      throw new Error(`ChatGPT composer not ready or login required. Textbox count: ${textboxCount}. Snapshot excerpt: ${snapshot.slice(0, 500)}`);
    }

    await textbox.fill(prompt, { timeoutMs: 15000 });
    await textbox.press("Enter", { timeoutMs: 15000 });
    await writeSession(fs, options.sessionPath, {
      Status: "submitted",
      SubmittedAt: new Date().toISOString(),
      ResponsePath: responsePath,
      AssetOutDir: outputDir,
    });
  }

  const waitResult = await waitForSettled(tab, options.maxWaitMs || 95000);
  snapshot = waitResult.snapshot;
  if (waitResult.timedOut && waitResult.busy) {
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
      ResumeHint: "Run chatgpt-chrome-bridge.mjs again with submitPrompt:false and newChat:false.",
    });
    await appendJsonLine(fs, eventsPath, {
      type: "waiting",
      at: new Date().toISOString(),
      project,
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
    ResponsePath: responsePath,
    HandoffPath: handoffPath,
    Assets: copiedAssets,
    HasPacket: result.hasPacket,
  });

  await appendJsonLine(fs, eventsPath, {
    type: "complete",
    at: new Date().toISOString(),
    project,
    responsePath,
    handoffPath,
    outputDir,
    assetCount: copiedAssets.length,
    hasPacket: result.hasPacket,
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
