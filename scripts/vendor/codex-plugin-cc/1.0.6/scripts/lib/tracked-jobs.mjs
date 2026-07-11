import fs from "node:fs";
import process from "node:process";

import { readJobFile, resolveJobFile, resolveJobLogFile, upsertJob, writeJobFile } from "./state.mjs";

export const SESSION_ID_ENV = "CODEX_COMPANION_SESSION_ID";

export function nowIso() {
  return new Date().toISOString();
}

function numericToken(value) {
  return Number.isFinite(Number(value)) ? Math.max(0, Math.trunc(Number(value))) : null;
}

export function buildRunMetrics(startedAt, completedAt, tokenUsage = null) {
  const startedMs = Date.parse(startedAt);
  const completedMs = Date.parse(completedAt);
  const elapsedMs = Number.isFinite(startedMs) && Number.isFinite(completedMs)
    ? Math.max(0, completedMs - startedMs)
    : null;
  const current = tokenUsage?.last ?? null;
  const cumulative = tokenUsage?.total ?? null;

  return {
    schemaVersion: "1.0",
    startedAt,
    completedAt,
    elapsedMs,
    tokenSource: tokenUsage?.source ?? (current ? "codex_app_server" : "unavailable"),
    inputTokens: numericToken(current?.inputTokens),
    cachedInputTokens: numericToken(current?.cachedInputTokens),
    outputTokens: numericToken(current?.outputTokens),
    reasoningOutputTokens: numericToken(current?.reasoningOutputTokens),
    totalTokens: numericToken(current?.totalTokens),
    threadTotalTokens: numericToken(cumulative?.totalTokens)
  };
}

export function formatRunUsage(metrics) {
  const elapsed = metrics?.elapsedMs == null ? "unavailable" : `${(metrics.elapsedMs / 1000).toFixed(3)}s`;
  const token = (value) => value == null ? "unavailable" : String(value);
  return [
    "RUN_USAGE",
    `elapsed=${elapsed}`,
    `tokens=${token(metrics?.totalTokens)}`,
    `input=${token(metrics?.inputTokens)}`,
    `cached_input=${token(metrics?.cachedInputTokens)}`,
    `output=${token(metrics?.outputTokens)}`,
    `reasoning_output=${token(metrics?.reasoningOutputTokens)}`,
    `source=${metrics?.tokenSource ?? "unavailable"}`
  ].join(" ");
}

function appendRunUsage(rendered, metrics) {
  const body = String(rendered ?? "").trimEnd();
  const usage = formatRunUsage(metrics);
  return body ? `${body}\n\n${usage}\n` : `${usage}\n`;
}

function normalizeProgressEvent(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return {
      message: String(value.message ?? "").trim(),
      phase: typeof value.phase === "string" && value.phase.trim() ? value.phase.trim() : null,
      threadId: typeof value.threadId === "string" && value.threadId.trim() ? value.threadId.trim() : null,
      turnId: typeof value.turnId === "string" && value.turnId.trim() ? value.turnId.trim() : null,
      stderrMessage: value.stderrMessage == null ? null : String(value.stderrMessage).trim(),
      logTitle: typeof value.logTitle === "string" && value.logTitle.trim() ? value.logTitle.trim() : null,
      logBody: value.logBody == null ? null : String(value.logBody).trimEnd()
    };
  }

  return {
    message: String(value ?? "").trim(),
    phase: null,
    threadId: null,
    turnId: null,
    stderrMessage: String(value ?? "").trim(),
    logTitle: null,
    logBody: null
  };
}

export function appendLogLine(logFile, message) {
  const normalized = String(message ?? "").trim();
  if (!logFile || !normalized) {
    return;
  }
  fs.appendFileSync(logFile, `[${nowIso()}] ${normalized}\n`, "utf8");
}

export function appendLogBlock(logFile, title, body) {
  if (!logFile || !body) {
    return;
  }
  fs.appendFileSync(logFile, `\n[${nowIso()}] ${title}\n${String(body).trimEnd()}\n`, "utf8");
}

export function createJobLogFile(workspaceRoot, jobId, title) {
  const logFile = resolveJobLogFile(workspaceRoot, jobId);
  fs.writeFileSync(logFile, "", "utf8");
  if (title) {
    appendLogLine(logFile, `Starting ${title}.`);
  }
  return logFile;
}

export function createJobRecord(base, options = {}) {
  const env = options.env ?? process.env;
  const sessionId = env[options.sessionIdEnv ?? SESSION_ID_ENV];
  return {
    ...base,
    createdAt: nowIso(),
    ...(sessionId ? { sessionId } : {})
  };
}

export function createJobProgressUpdater(workspaceRoot, jobId) {
  let lastPhase = null;
  let lastThreadId = null;
  let lastTurnId = null;

  return (event) => {
    const normalized = normalizeProgressEvent(event);
    const patch = { id: jobId };
    let changed = false;

    if (normalized.phase && normalized.phase !== lastPhase) {
      lastPhase = normalized.phase;
      patch.phase = normalized.phase;
      changed = true;
    }

    if (normalized.threadId && normalized.threadId !== lastThreadId) {
      lastThreadId = normalized.threadId;
      patch.threadId = normalized.threadId;
      changed = true;
    }

    if (normalized.turnId && normalized.turnId !== lastTurnId) {
      lastTurnId = normalized.turnId;
      patch.turnId = normalized.turnId;
      changed = true;
    }

    if (!changed) {
      return;
    }

    upsertJob(workspaceRoot, patch);

    const jobFile = resolveJobFile(workspaceRoot, jobId);
    if (!fs.existsSync(jobFile)) {
      return;
    }

    const storedJob = readJobFile(jobFile);
    writeJobFile(workspaceRoot, jobId, {
      ...storedJob,
      ...patch
    });
  };
}

export function createProgressReporter({ stderr = false, logFile = null, onEvent = null } = {}) {
  if (!stderr && !logFile && !onEvent) {
    return null;
  }

  return (eventOrMessage) => {
    const event = normalizeProgressEvent(eventOrMessage);
    const stderrMessage = event.stderrMessage ?? event.message;
    if (stderr && stderrMessage) {
      process.stderr.write(`[codex] ${stderrMessage}\n`);
    }
    appendLogLine(logFile, event.message);
    appendLogBlock(logFile, event.logTitle, event.logBody);
    onEvent?.(event);
  };
}

function readStoredJobOrNull(workspaceRoot, jobId) {
  const jobFile = resolveJobFile(workspaceRoot, jobId);
  if (!fs.existsSync(jobFile)) {
    return null;
  }
  return readJobFile(jobFile);
}

export async function runTrackedJob(job, runner, options = {}) {
  const runningRecord = {
    ...job,
    status: "running",
    startedAt: nowIso(),
    phase: "starting",
    pid: process.pid,
    logFile: options.logFile ?? job.logFile ?? null
  };
  writeJobFile(job.workspaceRoot, job.id, runningRecord);
  upsertJob(job.workspaceRoot, runningRecord);

  try {
    const execution = await runner();
    const completionStatus = execution.exitStatus === 0 ? "completed" : "failed";
    const completedAt = nowIso();
    const runMetrics = buildRunMetrics(runningRecord.startedAt, completedAt, execution.tokenUsage);
    const payload = {
      ...(execution.payload ?? {}),
      runMetrics
    };
    const rendered = appendRunUsage(execution.rendered, runMetrics);
    writeJobFile(job.workspaceRoot, job.id, {
      ...runningRecord,
      status: completionStatus,
      threadId: execution.threadId ?? null,
      turnId: execution.turnId ?? null,
      pid: null,
      phase: completionStatus === "completed" ? "done" : "failed",
      completedAt,
      runMetrics,
      result: payload,
      rendered
    });
    upsertJob(job.workspaceRoot, {
      id: job.id,
      status: completionStatus,
      threadId: execution.threadId ?? null,
      turnId: execution.turnId ?? null,
      summary: execution.summary,
      phase: completionStatus === "completed" ? "done" : "failed",
      pid: null,
      completedAt,
      runMetrics
    });
    appendLogBlock(options.logFile ?? job.logFile ?? null, "Final output", rendered);
    return {
      ...execution,
      payload,
      rendered,
      runMetrics
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const existing = readStoredJobOrNull(job.workspaceRoot, job.id) ?? runningRecord;
    const completedAt = nowIso();
    const runMetrics = buildRunMetrics(runningRecord.startedAt, completedAt, null);
    const rendered = appendRunUsage(existing.rendered ?? errorMessage, runMetrics);
    writeJobFile(job.workspaceRoot, job.id, {
      ...existing,
      status: "failed",
      phase: "failed",
      errorMessage,
      pid: null,
      completedAt,
      runMetrics,
      rendered,
      logFile: options.logFile ?? job.logFile ?? existing.logFile ?? null
    });
    upsertJob(job.workspaceRoot, {
      id: job.id,
      status: "failed",
      phase: "failed",
      pid: null,
      errorMessage,
      completedAt,
      runMetrics
    });
    appendLogBlock(options.logFile ?? job.logFile ?? null, "Run usage", formatRunUsage(runMetrics));
    throw error;
  }
}
