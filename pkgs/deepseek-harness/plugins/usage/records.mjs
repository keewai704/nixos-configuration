import { createReadStream } from "node:fs";
import { opendir, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { createInterface } from "node:readline";
import { Readable } from "node:stream";
import { StringDecoder } from "node:string_decoder";
import { zstdDecompressSync } from "node:zlib";

const counter = (value) => value === undefined ? 0 : Number.isSafeInteger(value) && value >= 0 ? value : null;
const timestamp = (value) => typeof value === "number" && Number.isFinite(value) && value > 0 ? value
  : typeof value === "string" && Number.isFinite(Date.parse(value)) ? Date.parse(value) : null;
const speed = (value) => value === "priority" || value === "fast" ? "fast" : value === "ultrafast" ? "ultrafast" : "standard";
const usageFields = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"];

export const totalTokens = (totals) => totals.input + totals.cacheRead + totals.cacheWrite + totals.output;

export function claudeRecord(row) {
  if (row.type !== "assistant" || !row.message?.usage) return null;
  const { message } = row;
  const at = timestamp(row.timestamp);
  if (at === null || typeof message.model !== "string" || !message.model || message.model === "<synthetic>") return null;
  const raw = message.usage;
  const totals = {
    input: counter(raw.input_tokens),
    cacheRead: counter(raw.cache_read_input_tokens),
    cacheWrite: counter(raw.cache_creation_input_tokens),
    output: counter(raw.output_tokens),
    reasoning: 0,
  };
  if (Object.values(totals).includes(null)) throw new Error("Invalid Claude usage counters");
  return {
    provider: "claude", at, model: message.model, session: row.sessionId ?? "",
    totals, speed: speed(raw.speed),
    reportedCost: typeof row.costUSD === "number" && Number.isFinite(row.costUSD) && row.costUSD >= 0 ? row.costUSD : null,
    key: typeof message.id === "string" || typeof row.requestId === "string" ? `claude:${message.id ?? ""}:${row.requestId ?? ""}` : null,
  };
}

function codexCounters(raw) {
  if (!raw || typeof raw !== "object") return null;
  const value = Object.fromEntries(usageFields.map((field) => [field, counter(raw[field])]));
  if (raw.input_tokens === undefined || raw.output_tokens === undefined) return null;
  if (raw.total_tokens === undefined) value.total_tokens = value.input_tokens + value.output_tokens;
  if (Object.values(value).includes(null)
    || value.cached_input_tokens + value.cache_write_input_tokens > value.input_tokens
    || value.reasoning_output_tokens > value.output_tokens
    || value.total_tokens < value.input_tokens + value.output_tokens) return null;
  return value;
}

export function codexState() {
  return { model: "", session: "", turn: "", provider: "", tierKnown: false, speed: "standard", previous: null, signature: null, meta: false, forkAnchor: null };
}

export function codexRecord(row, state) {
  const payload = row.payload;
  if (!payload || typeof payload !== "object") return null;
  if (row.type === "session_meta") {
    if (state.meta) return null;
    state.meta = true;
    state.session = payload.id ?? payload.session_id ?? "";
    state.provider = payload.model_provider ?? "";
    if (payload.forked_from_id || payload.source?.subagent?.thread_spawn?.parent_thread_id) state.forkAnchor = timestamp(row.timestamp);
    return null;
  }
  if (row.type === "turn_context") {
    if (typeof payload.model === "string") state.model = payload.model;
    if (typeof payload.turn_id === "string") state.turn = payload.turn_id;
    return null;
  }
  if (payload.type === "thread_settings_applied") {
    state.tierKnown = true;
    state.speed = speed(payload.thread_settings?.service_tier);
    return null;
  }
  if (payload.type !== "token_count" || !payload.info) return null;
  const at = timestamp(row.timestamp);
  if (at === null || !state.model) return null;
  const last = codexCounters(payload.info.last_token_usage);
  const hasCumulative = payload.info.total_token_usage != null;
  const cumulative = codexCounters(payload.info.total_token_usage);
  const previous = state.previous;
  if (cumulative) state.previous = cumulative;
  const signature = last ? JSON.stringify(last) : null;
  if (state.forkAnchor !== null && at - state.forkAnchor < 1_000) {
    state.forkAnchor = at;
    if (!hasCumulative && last && signature !== state.signature) {
      state.previous = codexCounters(Object.fromEntries(usageFields.map((field) => [field, (previous?.[field] ?? 0) + last[field]])));
    }
    state.signature = signature;
    return null;
  }
  if (state.forkAnchor !== null) { state.forkAnchor = null; state.signature = null; }
  if (!last || hasCumulative && !cumulative) throw new Error("Invalid Codex usage counters");
  if (last.input_tokens + last.output_tokens === 0) { state.signature = null; return null; }
  if (cumulative && previous && usageFields.every((field) => cumulative[field] === previous[field])) return null;
  if (last.total_tokens !== last.input_tokens + last.output_tokens) throw new Error("Invalid Codex request totals");
  if (cumulative) {
    const restarted = usageFields.every((field) => cumulative[field] === last[field]);
    const reconciled = previous
      ? usageFields.every((field) => cumulative[field] - previous[field] === last[field])
      : codexCounters(Object.fromEntries(usageFields.map((field) => [field, cumulative[field] - last[field]]))) !== null;
    if (!restarted && !reconciled) throw new Error("Inconsistent Codex cumulative usage");
  } else {
    if (signature === state.signature) return null;
    state.previous = codexCounters(Object.fromEntries(usageFields.map((field) => [field, (previous?.[field] ?? 0) + last[field]])));
    if (!state.previous) throw new Error("Invalid Codex cumulative usage");
  }
  state.signature = signature;
  return {
    provider: "chatgpt", at, model: state.model, session: state.session,
    key: state.session ? `codex:${state.session}:${state.turn}:${at}:${signature}` : null,
    unresolvedTurn: !state.tierKnown && state.provider === "openai" && state.turn ? state.turn : null,
    reportedCost: null, speed: state.speed,
    totals: {
      input: last.input_tokens - last.cached_input_tokens - last.cache_write_input_tokens,
      cacheRead: last.cached_input_tokens, cacheWrite: last.cache_write_input_tokens,
      output: last.output_tokens, reasoning: last.reasoning_output_tokens,
    },
  };
}

export function dshRecord(row) {
  if (row.type !== "assistant/message" || !row.data?.usage) return null;
  const source = row.data.message?.source;
  if (source?.provider !== "codex-local") return null;
  const at = timestamp(row.time);
  if (at === null || typeof source.model !== "string") return null;
  const raw = row.data.usage;
  const totals = {
    input: counter(raw.inputTokens), cacheRead: counter(raw.cacheReadTokens),
    cacheWrite: counter(raw.cacheWriteTokens), output: counter(raw.outputTokens),
    reasoning: counter(raw.reasoningTokens),
  };
  if (Object.values(totals).includes(null) || totals.reasoning > totals.output) throw new Error("Invalid DSH usage counters");
  const metadata = source.replayState?.response?.subscriptionUsage;
  const model = metadata?.model ?? source.model;
  if (typeof model !== "string" || !model) throw new Error("Invalid DSH usage model");
  return {
    provider: "chatgpt", at, model,
    session: "", totals, reportedCost: null, speed: speed(metadata?.speed),
    key: typeof row.data.message.id === "string" ? `dsh:${row.data.message.id}` : null,
  };
}

async function* decodedChunks(path, diagnostics) {
  if (!path.endsWith(".zstd")) { yield* createReadStream(path); return; }
  let pending = Buffer.alloc(0);
  for await (const chunk of createReadStream(path, { highWaterMark: 65_536 })) {
    pending = Buffer.concat([pending, chunk]);
    if (pending.length > 32 * 1024 * 1024) throw new Error("Compressed usage record is too large");
    while (pending.length) {
      let result;
      try {
        result = zstdDecompressSync(pending, { info: true, maxOutputLength: 64 * 1024 * 1024 });
      } catch (error) {
        if (error.code === "Z_BUF_ERROR") break;
        throw error;
      }
      if (!result.engine.bytesWritten) throw new Error("Compressed usage reader did not advance");
      pending = pending.subarray(result.engine.bytesWritten);
      yield result.buffer;
    }
  }
  if (pending.length) diagnostics.malformed++;
}

export async function readRecords(path, kind, cutoff = 0) {
  const diagnostics = { malformed: 0 };
  const records = [];
  const state = codexState();
  const decoder = new StringDecoder("utf8");
  const input = Readable.from((async function* () {
    for await (const chunk of decodedChunks(path, diagnostics)) yield decoder.write(chunk);
    yield decoder.end();
  })());
  const lines = createInterface({ input, crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (!line.trim()) continue;
      if (kind === "claude" && !line.includes('"usage"')) continue;
      if (kind === "dsh" && !line.includes('"assistant/message"')) continue;
      try {
        const row = JSON.parse(line);
        const record = kind === "claude" ? claudeRecord(row) : kind === "codex" ? codexRecord(row, state) : dshRecord(row);
        if (record && record.at >= cutoff && totalTokens(record.totals) > 0) {
          if (!record.session) record.session = basename(path);
          records.push(record);
        }
      } catch { diagnostics.malformed++; }
    }
  } finally {
    lines.close();
    input.destroy();
  }
  return { records, ...diagnostics };
}

export async function* historyFiles(root, kind) {
  const directory = await opendir(root);
  for await (const entry of directory) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) yield* historyFiles(path, kind);
    else if (entry.isFile() && (kind === "dsh"
      ? entry.name.startsWith("session") && /\.jsonl(?:\.zstd)?$/.test(entry.name)
      : entry.name.endsWith(".jsonl"))) yield path;
  }
}

export async function scanHistories(sources, cache, now = Date.now()) {
  const cutoff = now - 92 * 86_400_000;
  const records = [];
  const statuses = [];
  const live = new Set();
  for (const source of sources) {
    const status = { id: source.id, status: "ok", scannedFiles: 0, malformedRecords: 0, skippedFiles: 0 };
    let foundRoot = false;
    for (const root of source.roots) {
      try {
        for await (const path of historyFiles(root, source.kind)) {
          foundRoot = true;
          live.add(path);
          try {
            const info = await stat(path);
            if (info.mtimeMs < cutoff) continue;
            let entry = cache.get(path);
            if (!entry || entry.size !== info.size || entry.mtimeMs !== info.mtimeMs) {
              entry = { ...await readRecords(path, source.kind, cutoff), size: info.size, mtimeMs: info.mtimeMs };
              cache.set(path, entry);
            }
            status.scannedFiles++;
            status.malformedRecords += entry.malformed;
            for (const record of entry.records) records.push(record);
          } catch { status.skippedFiles++; }
        }
      } catch (error) {
        if (error.code !== "ENOENT") status.skippedFiles++;
      }
    }
    if (!foundRoot && !status.skippedFiles) status.status = "missing";
    else if (status.skippedFiles || status.malformedRecords) status.status = "partial";
    statuses.push(status);
  }
  for (const path of cache.keys()) if (!live.has(path)) cache.delete(path);
  return { records, sources: statuses };
}
