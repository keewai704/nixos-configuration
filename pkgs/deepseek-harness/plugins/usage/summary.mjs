import { totalTokens } from "./records.mjs";
import { priceRecord } from "./prices.mjs";

const HOUR = 3_600_000;
const emptyTotals = () => ({ input: 0, cacheRead: 0, cacheWrite: 0, output: 0, reasoning: 0 });
const dateFormatters = new Map();

export function validateWindow(input) {
  if (!input || !["24h", "7d", "30d", "90d"].includes(input.period) || typeof input.timeZone !== "string" || /^[+-]/.test(input.timeZone)) throw new Error("Invalid usage window");
  new Intl.DateTimeFormat("en", { timeZone: input.timeZone }).format();
  const provider = input.provider ?? "all";
  if (!["all", "claude", "chatgpt"].includes(provider) || input.model !== undefined && (typeof input.model !== "string" || input.model.length > 256)) throw new Error("Invalid usage filter");
  return { period: input.period, timeZone: input.timeZone, provider, model: input.model ?? "" };
}

export function dateKey(at, timeZone) {
  if (!dateFormatters.has(timeZone)) dateFormatters.set(timeZone, new Intl.DateTimeFormat("en", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }));
  const parts = dateFormatters.get(timeZone).formatToParts(at);
  const part = (type) => parts.find((value) => value.type === type).value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function emptyBucket(extra = {}) {
  return {
    ...extra, tokens: emptyTotals(), cost: 0, categories: { input: 0, cacheRead: 0, cacheWrite: 0, output: 0, other: 0 },
    speedCost: { standard: 0, fast: 0, ultrafast: 0 }, premium: 0, savings: 0,
    records: 0, unpricedRecords: 0, unpricedTokens: 0, sessions: new Set(),
  };
}

function add(bucket, record, price) {
  for (const key of Object.keys(bucket.tokens)) bucket.tokens[key] += record.totals[key];
  bucket.records++;
  bucket.sessions.add(`${record.provider}:${record.session}`);
  if (price.cost === null) { bucket.unpricedRecords++; bucket.unpricedTokens += totalTokens(record.totals); return; }
  bucket.cost += price.cost;
  bucket.speedCost[record.speed] += price.cost;
  bucket.savings += price.savings;
  bucket.premium += price.premium;
  if (price.categories) for (const [key, value] of Object.entries(price.categories)) bucket.categories[key] += value;
  else bucket.categories.other += price.cost;
}

const finish = (bucket) => ({ ...bucket, sessions: bucket.sessions.size, totalTokens: totalTokens(bucket.tokens) });

export function summarize(records, input, table, overrides = {}, now = Date.now()) {
  const { period, timeZone, provider, model } = validateWindow(input);
  const today = dateKey(now, timeZone);
  const days = Number.parseInt(period);
  const dayKeys = [];
  if (period !== "24h") {
    for (let offset = days - 1; offset >= 0; offset--) {
      const date = new Date(`${today}T12:00:00Z`);
      date.setUTCDate(date.getUTCDate() - offset);
      dayKeys.push(date.toISOString().slice(0, 10));
    }
  }
  const since = now - 24 * HOUR;
  const series = new Map((period === "24h"
    ? Array.from({ length: 24 }, (_, index) => new Date(since + index * HOUR).toISOString())
    : dayKeys).map((key) => [key, emptyBucket({ key })]));
  const models = new Map();
  const totals = emptyBucket();
  const availableModels = new Map();
  const seen = new Set();
  let duplicates = 0;
  for (const record of records) {
    if (record.key) {
      if (seen.has(record.key)) { duplicates++; continue; }
      seen.add(record.key);
    }
    if (record.at > now) continue;
    const key = period === "24h"
      ? record.at >= since ? new Date(since + Math.floor((record.at - since) / HOUR) * HOUR).toISOString() : ""
      : dateKey(record.at, timeZone);
    const bucket = series.get(key);
    if (!bucket) continue;
    const id = JSON.stringify([record.provider, record.model]);
    availableModels.set(id, { provider: record.provider, model: record.model });
    if (provider !== "all" && record.provider !== provider || model && record.model !== model) continue;
    if (!models.has(id)) models.set(id, emptyBucket({ provider: record.provider, model: record.model }));
    const price = priceRecord(record, table, overrides);
    add(bucket, record, price);
    add(models.get(id), record, price);
    add(totals, record, price);
  }
  return {
    readAt: new Date(now).toISOString(), period, timeZone, provider, model, duplicates,
    availableModels: [...availableModels.values()].sort((left, right) => left.model.localeCompare(right.model)),
    totals: finish(totals),
    series: [...series.values()].map(finish),
    models: [...models.values()].map(finish).sort((left, right) => right.totalTokens - left.totalTokens),
  };
}
