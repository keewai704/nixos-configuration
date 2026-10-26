import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { zstdCompressSync } from "node:zlib";
import { claudeRecord, codexRecord, codexState, dshRecord, readRecords, totalTokens } from "./records.mjs";
import { normalizeLimits } from "./limits.mjs";
import { parsePrices, priceRecord, validatePrices } from "./prices.mjs";
import { summarize } from "./summary.mjs";
import { resolveT3Tiers } from "./t3-tiers.mjs";

const at = "2026-11-02T01:00:00.000Z";
const row = (id = "message-1") => ({
  type: "assistant", timestamp: at, sessionId: "session-1", requestId: "request-1",
  message: { id, model: "vendor-new-model", usage: { input_tokens: 10, cache_read_input_tokens: 100, cache_creation_input_tokens: 5, output_tokens: 20 }, content: [{ type: "text", text: "PRIVATE_PROMPT_DO_NOT_RETURN" }] },
});
const counters = (input = 100, output = 20) => ({ input_tokens: input, cached_input_tokens: 40, cache_write_input_tokens: 10, output_tokens: output, reasoning_output_tokens: 5, total_tokens: input + output });
const countEvent = (last, cumulative = last, timestamp = at) => ({ type: "event_msg", timestamp, payload: { type: "token_count", info: { last_token_usage: last, total_token_usage: cumulative } } });
const dshRow = (id) => ({ type: "assistant/message", time: Date.parse(at), data: {
  message: { id, source: { kind: "model", provider: "codex-local", model: "vendor-new-model" } },
  usage: { inputTokens: 10, cacheReadTokens: 100, cacheWriteTokens: 5, outputTokens: 20, reasoningTokens: 8 },
} });

test("Claude block repeats count once and reasoning is not added to output", () => {
  const record = claudeRecord(row());
  assert.equal(totalTokens(record.totals), 135);
  const summary = summarize([record, claudeRecord(row())], { period: "7d", timeZone: "UTC" }, new Map(), {}, Date.parse(at) + 1);
  assert.equal(summary.totals.records, 1);
  assert.equal(summary.totals.totalTokens, 135);
  assert.equal(summary.duplicates, 1);
  assert.equal(JSON.stringify(summary).includes("PRIVATE_PROMPT"), false);
});

test("Codex re-emitted cumulative counters and invalid deltas are excluded", () => {
  const state = codexState();
  codexRecord({ type: "session_meta", payload: { id: "session-1" } }, state);
  codexRecord({ type: "turn_context", payload: { model: "vendor-future-model", turn_id: "turn-1" } }, state);
  const record = codexRecord(countEvent(counters()), state);
  assert.equal(totalTokens(record.totals), 120);
  assert.deepEqual(record.totals, { input: 50, cacheRead: 40, cacheWrite: 10, output: 20, reasoning: 5 });
  assert.equal(codexRecord(countEvent(counters()), state), null);
  assert.throws(() => codexRecord(countEvent(counters(110), counters(240, 45)), state), /Inconsistent/);
});

test("Codex fork copies establish a baseline without billing the parent again", () => {
  const state = codexState();
  codexRecord({ type: "session_meta", timestamp: at, payload: { id: "child", forked_from_id: "parent" } }, state);
  codexRecord({ type: "turn_context", payload: { model: "new-model" } }, state);
  assert.equal(codexRecord(countEvent(counters(), counters(), "2026-11-02T01:00:00.010Z"), state), null);
  const next = { ...counters(60, 10), cached_input_tokens: 0, cache_write_input_tokens: 0 };
  const cumulative = Object.fromEntries(Object.keys(next).map((key) => [key, counters()[key] + next[key]]));
  assert.equal(totalTokens(codexRecord(countEvent(next, cumulative, "2026-11-02T01:00:05Z"), state).totals), 70);
});

test("DSH keeps disjoint cache counters and excludes persisted Claude SDK calls", () => {
  assert.equal(totalTokens(dshRecord(dshRow("message-1")).totals), 135);
  const claude = dshRow("duplicate");
  claude.data.message.source.provider = "claude-bridge";
  assert.equal(dshRecord(claude), null);
});

test("all concatenated Zstandard frames are scanned and a torn tail is reported", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dsh-usage-frames-"));
  try {
    const frames = [dshRow("first"), dshRow("second"), dshRow("torn")].map((value) => zstdCompressSync(Buffer.from(`${JSON.stringify(value)}\n`)));
    const path = join(dir, "session.v4.jsonl.zstd");
    await writeFile(path, Buffer.concat([frames[0], frames[1], frames[2].subarray(0, -3)]));
    const result = await readRecords(path, "dsh");
    assert.equal(result.records.length, 2);
    assert.equal(result.malformed, 1);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("unknown prices stay unknown while a deliberate zero price is priced", () => {
  const record = claudeRecord(row());
  assert.equal(priceRecord(record, new Map()).cost, null);
  assert.equal(priceRecord(record, new Map(), { "vendor-new-model": { input: 0, output: 0 } }).cost, 0);
  assert.throws(() => validatePrices({ bad: { input: -1, output: 0 } }), /Invalid/);
});

test("cache prices and speed premiums use output once, including reasoning", () => {
  const table = parsePrices({ "vendor-new-model": { input_cost_per_token: 2, output_cost_per_token: 4, cache_read_input_token_cost: 1, cache_creation_input_token_cost: 3, provider_specific_entry: { fast: 2 } } });
  const record = { ...claudeRecord(row()), speed: "fast" };
  record.totals.reasoning = 8;
  const price = priceRecord(record, table);
  assert.equal(price.cost, 430);
  assert.equal(price.premium, 215);
  assert.equal(price.savings, 200);
});

test("calendar windows respect the selected IANA time zone across DST", () => {
  const record = claudeRecord(row());
  const summary = summarize([record], { period: "7d", timeZone: "America/New_York" }, new Map(), {}, Date.parse("2026-11-02T02:00Z"));
  assert.equal(summary.series.length, 7);
  assert.equal(summary.series.at(-1).key, "2026-11-01");
  assert.equal(summary.series.at(-1).totalTokens, 135);
  assert.throws(() => summarize([], { period: "7d", timeZone: "invalid/zone" }, new Map()), /time zone/i);
});

test("an exhausted weekly allowance blocks otherwise available session quota", () => {
  const result = normalizeLimits("claude", { plan: "Pro", rate_limits_available: true, rate_limits: {
    five_hour: { utilization: 20, resets_at: "2026-11-02T04:00Z" }, seven_day: { utilization: 100, resets_at: "2026-11-03T00:00Z" },
  } }, Date.parse(at));
  assert.equal(result.windows[0].remainingPercent, 0);
  assert.equal(result.windows[0].rawRemainingPercent, 80);
  assert.equal(result.windows[0].nextAvailableAt, "2026-11-03T00:00:00.000Z");
  assert.equal(normalizeLimits("chatgpt", { plan: "free", rateLimits: { primary: { usedPercent: 5 } } }).windows[0].label, "monthly");
  assert.equal(normalizeLimits("chatgpt", {}).status, "unavailable");
});

test("T3 service tiers use the first running selection and leave its database unchanged", async () => {
  const { DatabaseSync } = await import("node:sqlite");
  const { readFile } = await import("node:fs/promises");
  const directory = await mkdtemp(join(tmpdir(), "dsh-t3-tiers-"));
  const path = join(directory, "statev2.sqlite");
  try {
    const database = new DatabaseSync(path);
    database.exec(`
      CREATE TABLE orchestration_events (aggregate_kind, application_event_version, stream_id, event_type, sequence, payload_json);
      CREATE TABLE orchestration_v2_projection_provider_turns (thread_id, provider_thread_id, run_attempt_id, payload_json);
      CREATE TABLE orchestration_v2_projection_run_attempts (thread_id, provider_thread_id, attempt_id, run_id, payload_json);
    `);
    database.prepare("INSERT INTO orchestration_v2_projection_run_attempts VALUES (?, ?, ?, ?, ?)").run("thread", "provider-thread", "attempt", "run", JSON.stringify({ nativeThreadId: "native-thread" }));
    database.prepare("INSERT INTO orchestration_v2_projection_provider_turns VALUES (?, ?, ?, ?)").run("thread", "provider-thread", "attempt", JSON.stringify({ nativeTurnRef: { driver: "codex", nativeId: "native-turn" } }));
    for (const [index, tier] of ["fast", "standard"].entries()) database.prepare("INSERT INTO orchestration_events VALUES (?, ?, ?, ?, ?, ?)").run("thread", 2, "thread", "run.updated", index, JSON.stringify({ id: "run", activeAttemptId: "attempt", status: "running", modelSelection: { model: "vendor-new-model", options: [{ id: "serviceTier", value: tier }] } }));
    database.close();
    const before = await readFile(path);
    const record = { ...claudeRecord(row()), provider: "chatgpt", session: "native-thread", unresolvedTurn: "native-turn" };
    const result = await resolveT3Tiers([record], path);
    assert.equal(result.records[0].speed, "fast");
    assert.equal(result.t3Tiers.matched, 1);
    assert.deepEqual(await readFile(path), before);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("the worker reads real files and returns aggregates without transcript text", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dsh-usage-worker-"));
  let worker;
  try {
    const projects = join(dir, "projects");
    await mkdir(projects);
    const record = row(); record.timestamp = new Date().toISOString();
    await writeFile(join(projects, "session.jsonl"), `${JSON.stringify(record)}\n${JSON.stringify(record)}\n`);
    await writeFile(join(dir, "prices.json"), JSON.stringify({ fetchedAt: new Date().toISOString(), document: { "vendor-new-model": { input_cost_per_token: 1, output_cost_per_token: 1 } } }));
    worker = new Worker(new URL("./worker.mjs", import.meta.url), { workerData: { stateDir: dir, sources: [{ id: "claude", kind: "claude", roots: [projects] }] } });
    const result = await new Promise((resolve, reject) => {
      worker.once("message", resolve); worker.once("error", reject);
      worker.postMessage({ id: 1, operation: "summary", payload: { period: "7d", timeZone: "UTC" } });
    });
    assert.equal(result.error, undefined);
    assert.equal(result.value.totals.totalTokens, 135);
    assert.equal(result.value.totals.sessions, 1);
    assert.equal(result.value.pricing.status, "cached");
    assert.equal(JSON.stringify(result).includes("PRIVATE_PROMPT"), false);
    assert.equal(JSON.stringify(result).includes(projects), false);
  } finally { await worker?.terminate(); await rm(dir, { recursive: true, force: true }); }
});
