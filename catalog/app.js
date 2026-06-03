const packs = [
  {
    id: "Core",
    name: "Core Operating System",
    risk: "medium",
    summary: "Owner buttons, Next protocol, gear routing, git guard, handoffs, and systems health checks.",
    tags: ["Everyone", "Fresh installs", "Guardrails"],
    examples: ["Next", "Create a goal", "Check the selected gear"]
  },
  {
    id: "Founder",
    name: "Founder Operator Pack",
    risk: "low",
    summary: "Scattered founder work becomes owner-only queues, handoffs, follow-ups, briefings, and crisp written outputs.",
    tags: ["Founders", "Agencies", "Handoffs"],
    examples: ["Extract owner buttons", "Draft client update", "Create handoff note"]
  },
  {
    id: "Builder",
    name: "Builder Automation Pack",
    risk: "high",
    summary: "Feature building, CI debugging, deploy prep, migrations, logs, reviews, and repo-safe shipping.",
    tags: ["Code", "CI", "Deploy"],
    examples: ["Debug failing build", "Review current diff", "Ship with tests"]
  },
  {
    id: "Designer",
    name: "Design Delivery Pack",
    risk: "medium",
    summary: "Frontend polish, brand consistency, visual deliverables, screenshot QA, and face-preserving image edits.",
    tags: ["Design", "Frontend", "Visual QA"],
    examples: ["Polish dashboard", "Create poster", "Preserve face pixels"]
  },
  {
    id: "Knowledge",
    name: "Knowledge Capture Pack",
    risk: "medium",
    summary: "Research, meetings, specs, and decisions become structured docs, Notion-ready pages, and implementation plans.",
    tags: ["Research", "Notion", "Specs"],
    examples: ["Decision record", "PRD to tasks", "Meeting brief"]
  },
  {
    id: "Revenue",
    name: "Revenue and Ops Pack",
    risk: "medium",
    summary: "Sales, ads, leads, support, invoices, spreadsheets, and customer-facing operations.",
    tags: ["Sales", "Ops", "Spreadsheets"],
    examples: ["Find leads", "Organize receipts", "Write formula"]
  },
  {
    id: "XHigh",
    name: "XHigh Council Pack",
    risk: "xhigh",
    summary: "Self-bounce, CEO/CTO/Programmer/QA council mode, and explicit guardrails before risky implementation.",
    tags: ["Architecture", "Auth", "Security"],
    examples: ["Council mode", "Bounce database plan", "Production-risk review"]
  }
];

const workflows = [
  {
    title: "Owner Button Workflow",
    label: "Ownership split",
    copy: "Codex does implementation, tests, debugging, commits, pushes, and handoffs. Humans only handle external account/session actions and approvals."
  },
  {
    title: "Reasoning Gears",
    label: "Low to xhigh",
    copy: "Tasks route through fast, balanced, deep, max, or review profiles. Risky work can self-bounce before implementation starts."
  },
  {
    title: "Git Guard",
    label: "Repo safety",
    copy: "Before commit, push, PR, deploy, branch creation, or destructive git operations, Codex verifies repo root, branch, remote, HEAD, and dirty files."
  },
  {
    title: "CEO/CTO/Programmer/QA Council",
    label: "XHigh work",
    copy: "Highest-risk implementation stages itself through requirements, technical approach, implementation, and QA review loops."
  },
  {
    title: "Project Freshness",
    label: "Left-bar markers",
    copy: "Saved Codex projects get freshness colors based on last modified time, with an after-exit helper for Desktop state refresh."
  },
  {
    title: "Portable Handoffs",
    label: "Move between machines",
    copy: "Codex can produce durable handoff notes and importable GitHub-backed setup for another session or computer."
  }
];

const selectedPacks = new Set();
let activeRisk = "all";

const packGrid = document.querySelector("#pack-grid");
const workflowGrid = document.querySelector("#workflow-grid");
const searchInput = document.querySelector("#search");
const installCommand = document.querySelector("#install-command");

function riskLabel(risk) {
  return risk === "xhigh" ? "XHigh" : risk.charAt(0).toUpperCase() + risk.slice(1);
}

function packSearchText(pack) {
  return [pack.id, pack.name, pack.risk, pack.summary, ...pack.tags, ...pack.examples].join(" ").toLowerCase();
}

function updateInstallCommand() {
  if (selectedPacks.size === 0) {
    installCommand.textContent = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\install.ps1";
    return;
  }

  const packList = Array.from(selectedPacks).join(",");
  installCommand.textContent = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\install.ps1 -Pack ${packList}`;
}

function renderPacks() {
  const term = searchInput.value.trim().toLowerCase();
  packGrid.innerHTML = "";

  packs
    .filter((pack) => activeRisk === "all" || pack.risk === activeRisk)
    .filter((pack) => !term || packSearchText(pack).includes(term))
    .forEach((pack) => {
      const article = document.createElement("article");
      article.className = "pack-card";
      article.innerHTML = `
        <div class="pack-top">
          <span class="pack-id">${pack.id}</span>
          <span class="risk ${pack.risk}">${riskLabel(pack.risk)}</span>
        </div>
        <div>
          <h3>${pack.name}</h3>
          <p>${pack.summary}</p>
        </div>
        <ul class="tag-list">${pack.tags.map((tag) => `<li>${tag}</li>`).join("")}</ul>
        <div class="card-actions">
          <button type="button" class="select-button ${selectedPacks.has(pack.id) ? "selected" : ""}" data-pack="${pack.id}">
            ${selectedPacks.has(pack.id) ? "Selected" : "Add to install"}
          </button>
        </div>
      `;
      packGrid.appendChild(article);
    });
}

function renderWorkflows() {
  workflowGrid.innerHTML = "";
  workflows.forEach((workflow) => {
    const article = document.createElement("article");
    article.className = "workflow-card";
    article.innerHTML = `
      <strong>${workflow.label}</strong>
      <h3>${workflow.title}</h3>
      <p>${workflow.copy}</p>
    `;
    workflowGrid.appendChild(article);
  });
}

document.addEventListener("click", async (event) => {
  const packButton = event.target.closest("[data-pack]");
  if (packButton) {
    const packId = packButton.dataset.pack;
    if (selectedPacks.has(packId)) selectedPacks.delete(packId);
    else selectedPacks.add(packId);
    updateInstallCommand();
    renderPacks();
    return;
  }

  const riskButton = event.target.closest("[data-risk]");
  if (riskButton) {
    activeRisk = riskButton.dataset.risk;
    document.querySelectorAll("[data-risk]").forEach((button) => button.classList.toggle("active", button === riskButton));
    renderPacks();
    return;
  }

  const copyButton = event.target.closest("[data-copy-target]");
  if (copyButton) {
    const target = document.getElementById(copyButton.dataset.copyTarget);
    const text = target ? target.textContent.trim() : "";
    if (!text) return;
    await navigator.clipboard.writeText(text);
    const oldText = copyButton.textContent;
    copyButton.textContent = "Copied";
    window.setTimeout(() => {
      copyButton.textContent = oldText;
    }, 1200);
  }
});

searchInput.addEventListener("input", renderPacks);
renderPacks();
renderWorkflows();
updateInstallCommand();
