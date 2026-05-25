#!/usr/bin/env node
import { execFile } from "node:child_process";
import { appendFile, mkdir, readFile } from "node:fs/promises";
import http from "node:http";

const host = process.env.T3_KOBO_BRIDGE_HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.T3_KOBO_BRIDGE_PORT ?? "18891", 10);
const baseDir = process.env.T3_KOBO_BASE_DIR ?? `${process.env.HOME ?? "."}/.t3`;
const defaultTarget = process.env.T3_KOBO_TARGET ?? "";
const t3Bin = process.env.T3_KOBO_T3_BIN ?? "t3";
const runtimeStatePath =
  process.env.T3_KOBO_RUNTIME_STATE ?? `${baseDir.replace(/\/+$/, "")}/userdata/server-runtime.json`;
const telemetryLogPath =
  process.env.T3_KOBO_TELEMETRY_LOG ?? `${baseDir.replace(/\/+$/, "")}/kobo-bridge/telemetry.ndjson`;
const maxMessageBytes = 12 * 1024;
const defaultLimit = 10;

let cachedSession = null;
let cachedSnapshot = null;
let cachedSnapshotAt = 0;
let snapshotRefreshPromise = null;

function respond(res, status, body, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "content-type": contentType,
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
  });
  res.end(body);
}

function respondJson(res, status, body) {
  respond(res, status, `${JSON.stringify(body)}\n`, "application/json; charset=utf-8");
}

function runT3(args) {
  return new Promise((resolve) => {
    execFile(
      t3Bin,
      args,
      {
        env: {
          ...process.env,
          NODE_NO_WARNINGS: "1",
        },
        timeout: 20_000,
        maxBuffer: 512 * 1024,
      },
      (error, stdout, stderr) => {
        resolve({
          ok: error === null,
          code: typeof error?.code === "number" ? error.code : error === null ? 0 : 1,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
        });
      },
    );
  });
}

async function readRuntimeOrigin() {
  const raw = await readFile(runtimeStatePath, "utf8");
  const state = JSON.parse(raw);
  if (!state.origin || typeof state.origin !== "string") {
    throw new Error(`Runtime state has no origin: ${runtimeStatePath}`);
  }
  return state.origin.replace(/\/+$/, "");
}

function sessionUsable(session) {
  if (!session?.token || !session?.expiresAt) {
    return false;
  }
  return Date.parse(session.expiresAt) - Date.now() > 60_000;
}

async function getSession() {
  if (sessionUsable(cachedSession)) {
    return cachedSession;
  }

  const result = await runT3([
    "--log-level",
    "error",
    "auth",
    "session",
    "issue",
    "--base-dir",
    baseDir,
    "--label",
    "kobo bridge",
    "--json",
  ]);
  if (!result.ok) {
    throw new Error([result.stdout, result.stderr].filter(Boolean).join("\n") || "Could not issue T3 session.");
  }

  cachedSession = JSON.parse(result.stdout);
  return cachedSession;
}

async function t3Request(path, options = {}) {
  const origin = await readRuntimeOrigin();
  const session = await getSession();
  const response = await fetch(`${origin}${path}`, {
    ...options,
    headers: {
      accept: "application/json",
      authorization: `Bearer ${session.token}`,
      ...(options.body ? { "content-type": "application/json" } : {}),
      ...(options.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) {
    let message = text;
    try {
      message = JSON.parse(text).error ?? text;
    } catch {
      // Keep the raw body.
    }
    throw new Error(message || `T3 API request failed with HTTP ${response.status}.`);
  }
  return text.length > 0 ? JSON.parse(text) : null;
}

async function getSnapshot() {
  return t3Request("/api/orchestration/snapshot");
}

async function refreshSnapshot() {
  if (!snapshotRefreshPromise) {
    snapshotRefreshPromise = getSnapshot()
      .then((snapshot) => {
        cachedSnapshot = snapshot;
        cachedSnapshotAt = Date.now();
        return snapshot;
      })
      .finally(() => {
        snapshotRefreshPromise = null;
      });
  }
  return snapshotRefreshPromise;
}

async function getSnapshotCached(input = {}) {
  const maxAgeMs = input.maxAgeMs ?? 10_000;
  const allowStale = input.allowStale ?? false;
  const ageMs = Date.now() - cachedSnapshotAt;
  if (cachedSnapshot && ageMs <= maxAgeMs) {
    return cachedSnapshot;
  }
  if (cachedSnapshot && allowStale) {
    void refreshSnapshot().catch(() => {});
    return cachedSnapshot;
  }
  return refreshSnapshot();
}

function activeThreads(snapshot) {
  return snapshot.threads
    .filter((thread) => thread.deletedAt === null && thread.archivedAt === null)
    .toSorted((left, right) => right.updatedAt.localeCompare(left.updatedAt));
}

function threadStatus(thread) {
  if (thread.session?.status) {
    return thread.session.status;
  }
  if (thread.latestTurn?.state === "running") {
    return "running";
  }
  return thread.latestTurn?.state ?? "idle";
}

function findThread(snapshot, target) {
  const needle = (target || defaultTarget).trim().replace(/^@/, "").toLowerCase();
  return (
    activeThreads(snapshot).find((thread) => {
      const title = thread.title.toLowerCase();
      return thread.id.toLowerCase() === needle || title === needle || title.replace(/\s+/g, "-") === needle;
    }) ?? null
  );
}

function projectTitle(snapshot, projectId) {
  return snapshot.projects.find((project) => project.id === projectId)?.title ?? projectId;
}

function formatAgentLine(snapshot, thread) {
  return [
    thread.id,
    thread.title.replace(/\s+/g, " "),
    threadStatus(thread),
    `${thread.modelSelection.instanceId}/${thread.modelSelection.model}`,
    projectTitle(snapshot, thread.projectId).replace(/\s+/g, " "),
    thread.updatedAt,
  ].join("\t");
}

function conciseText(value, maxChars = 1400) {
  const text = String(value ?? "").replace(/\r/g, "").trim();
  if (text.length <= maxChars) {
    return text;
  }
  return `${text.slice(0, maxChars - 1)}…`;
}

function isLikelyProgressMessage(text) {
  const trimmed = String(text ?? "").trim();
  if (trimmed.length === 0) {
    return true;
  }
  return /^(I('|’)ll|I('|’)m|I am|I('|’)ve|I have|Running|Executing|Checking|Next|Now|Looking|Fetching|Inspecting|Located|Found)\b/i.test(
    trimmed,
  );
}

function stripOperationalLines(text) {
  return String(text ?? "")
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      if (/^-?\s*`?(health|send|exit|cmd|command|stdout|stderr|status)=/i.test(trimmed)) {
        return false;
      }
      if (/^-?\s*`?(curl|wget|t3|node|bun|git|ssh|tailscale)\b/i.test(trimmed)) {
        return false;
      }
      return true;
    })
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function formatThreadText(thread, limit) {
  const entries = [];
  for (const message of thread.messages) {
    if (message.role === "user") {
      const text = conciseText(message.text, 900);
      if (text.length > 0) {
        entries.push(`You: ${text}`);
      }
      continue;
    }
    if (message.role === "assistant") {
      const text = stripOperationalLines(message.text);
      if (text.length > 0 && !isLikelyProgressMessage(text)) {
        const response = conciseText(text, 2200);
        if (entries[entries.length - 1] !== response) {
          entries.push(response);
        }
      }
    }
  }
  const visibleEntries = entries.slice(-limit * 2);
  if (visibleEntries.length === 0) {
    return "No messages yet.\n";
  }
  return `${visibleEntries.join("\n\n")}\n`;
}

function makeTurnCommand(thread, message) {
  const now = new Date().toISOString();
  return {
    type: "thread.turn.start",
    commandId: crypto.randomUUID(),
    threadId: thread.id,
    message: {
      messageId: crypto.randomUUID(),
      role: "user",
      text: message,
      attachments: [],
    },
    titleSeed: thread.title,
    runtimeMode: thread.runtimeMode,
    interactionMode: thread.interactionMode,
    createdAt: now,
  };
}

async function handleAgents(url, res) {
  const format = url.searchParams.get("format") ?? "text";
  const snapshot = await getSnapshotCached({ allowStale: true, maxAgeMs: 5_000 });
  const threads = activeThreads(snapshot);
  const agents = threads.map((thread) => ({
    id: thread.id,
    title: thread.title,
    status: threadStatus(thread),
    model: `${thread.modelSelection.instanceId}/${thread.modelSelection.model}`,
    project: projectTitle(snapshot, thread.projectId),
    updatedAt: thread.updatedAt,
  }));
  if (format === "json") {
    respondJson(res, 200, { agents });
    return;
  }
  respond(res, 200, `${threads.map((thread) => formatAgentLine(snapshot, thread)).join("\n")}\n`);
}

async function handleThread(url, res) {
  const target = url.searchParams.get("target") ?? defaultTarget;
  const limit = Math.max(1, Math.min(50, Number.parseInt(url.searchParams.get("limit") ?? `${defaultLimit}`, 10)));
  const format = url.searchParams.get("format") ?? "text";
  const snapshot = await getSnapshotCached({ allowStale: true, maxAgeMs: 3_000 });
  const thread = findThread(snapshot, target);
  if (!thread) {
    respond(res, 404, `No active T3 thread found for '${target}'.\n`);
    return;
  }
  if (format === "json") {
    respondJson(res, 200, {
      thread: {
        id: thread.id,
        title: thread.title,
        status: threadStatus(thread),
        model: `${thread.modelSelection.instanceId}/${thread.modelSelection.model}`,
        updatedAt: thread.updatedAt,
        messages: thread.messages.slice(-limit).map((message) => ({
          id: message.id,
          role: message.role,
          text: message.text,
          streaming: message.streaming,
          createdAt: message.createdAt,
          updatedAt: message.updatedAt,
        })),
      },
    });
    return;
  }
  respond(res, 200, formatThreadText(thread, limit));
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function handleStream(url, res) {
  const target = url.searchParams.get("target") ?? defaultTarget;
  const limit = Math.max(1, Math.min(50, Number.parseInt(url.searchParams.get("limit") ?? `${defaultLimit}`, 10)));
  const seconds = Math.max(5, Math.min(180, Number.parseInt(url.searchParams.get("seconds") ?? "120", 10)));
  const intervalMs = Math.max(750, Math.min(5_000, Number.parseInt(url.searchParams.get("interval_ms") ?? "1500", 10)));
  const startedAt = Date.now();
  let lastBody = "";
  let stableAfterDone = 0;
  let closed = false;

  reqSafeOnClose(res, () => {
    closed = true;
  });

  res.writeHead(200, {
    "content-type": "text/plain; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    connection: "close",
  });

  while (!closed && Date.now() - startedAt < seconds * 1000) {
    const snapshot = await getSnapshotCached({ allowStale: false, maxAgeMs: intervalMs });
    const thread = findThread(snapshot, target);
    if (!thread) {
      res.write(`\x1eNo active T3 thread found for '${target}'.\n`);
      break;
    }

    const body = formatThreadText(thread, limit);
    if (body !== lastBody) {
      lastBody = body;
      res.write(`\x1e${body}`);
    }

    if (threadStatus(thread) !== "running") {
      stableAfterDone += 1;
      if (stableAfterDone >= 3) {
        break;
      }
    } else {
      stableAfterDone = 0;
    }

    await wait(intervalMs);
  }

  res.end();
}

function reqSafeOnClose(res, callback) {
  res.on("close", callback);
  res.on("error", callback);
}

async function handleSend(url, res) {
  const message = (url.searchParams.get("message") ?? "").trim();
  const target = (url.searchParams.get("target") ?? defaultTarget).trim();
  if (target.length === 0) {
    respond(res, 400, "Missing target.\n");
    return;
  }
  if (message.length === 0) {
    respond(res, 400, "Missing message.\n");
    return;
  }
  if (Buffer.byteLength(message, "utf8") > maxMessageBytes) {
    respond(res, 413, "Message too large.\n");
    return;
  }

  const snapshot = await getSnapshotCached({ allowStale: true, maxAgeMs: 10_000 });
  const thread = findThread(snapshot, target);
  if (!thread) {
    respond(res, 404, `No active T3 thread found for '${target}'.\n`);
    return;
  }
  await t3Request("/api/orchestration/dispatch", {
    method: "POST",
    body: JSON.stringify(makeTurnCommand(thread, message)),
  });
  setTimeout(() => {
    void refreshSnapshot().catch(() => {});
  }, 1_500);
  respond(res, 200, `sent\t${thread.id}\t${thread.title}\n`);
}

async function handleTelemetry(url, res) {
  const event = {
    receivedAt: new Date().toISOString(),
    source: url.searchParams.get("source") ?? "kobo",
    kind: url.searchParams.get("kind") ?? "event",
    message: url.searchParams.get("message") ?? "",
  };
  await mkdir(telemetryLogPath.slice(0, telemetryLogPath.lastIndexOf("/")), { recursive: true });
  await appendFile(telemetryLogPath, `${JSON.stringify(event)}\n`, "utf8");
  respond(res, 200, "ok\n");
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? `${host}:${port}`}`);
  if (req.method !== "GET") {
    respond(res, 405, "Only GET is supported.\n");
    return;
  }

  const handler =
    url.pathname === "/health" || url.pathname === "/status"
      ? async () => {
          const origin = await readRuntimeOrigin();
          respond(res, 200, `ok target=${defaultTarget} baseDir=${baseDir} origin=${origin}\n`);
        }
      : url.pathname === "/agents"
        ? () => handleAgents(url, res)
        : url.pathname === "/thread"
        ? () => handleThread(url, res)
        : url.pathname === "/stream"
        ? () => handleStream(url, res)
        : url.pathname === "/send"
          ? () => handleSend(url, res)
          : url.pathname === "/telemetry"
            ? () => handleTelemetry(url, res)
            : null;

  if (!handler) {
    respond(res, 404, "Not found.\n");
    return;
  }

  handler().catch((error) => {
    respond(res, 500, `Bridge error: ${error instanceof Error ? error.message : String(error)}\n`);
  });
});

server.listen(port, host, () => {
  console.log(`t3-kobo-bridge listening on http://${host}:${port}`);
});
