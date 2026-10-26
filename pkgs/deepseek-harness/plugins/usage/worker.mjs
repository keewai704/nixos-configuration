import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { parentPort, workerData } from "node:worker_threads";
import { scanHistories } from "./records.mjs";
import { parsePrices, PRICES_URL, validatePrices } from "./prices.mjs";
import { summarize, validateWindow } from "./summary.mjs";
import { resolveT3Tiers } from "./t3-tiers.mjs";

const cache = new Map();
const pricesPath = join(workerData.stateDir, "prices.json");
const overridesPath = join(workerData.stateDir, "price-overrides.json");
let prices;
let overrides;
let pricing;
let lastAttempt = 0;

async function readJson(path) {
  try { return JSON.parse(await readFile(path, "utf8")); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

async function saveJson(path, value) {
  await mkdir(workerData.stateDir, { recursive: true, mode: 0o700 });
  const temporary = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(value), { mode: 0o600 });
  await rename(temporary, path);
}

async function loadPrices(force = false) {
  if (!pricing) {
    const saved = await readJson(pricesPath);
    prices = parsePrices(saved?.document);
    pricing = { status: prices.size ? "cached" : "unavailable", source: PRICES_URL, fetchedAt: saved?.fetchedAt ?? null };
  }
  const age = Date.now() - Date.parse(pricing.fetchedAt);
  if (Date.now() - lastAttempt < 60_000 || !force && age < 86_400_000) return;
  lastAttempt = Date.now();
  try {
    const response = await fetch(PRICES_URL, { signal: AbortSignal.timeout(15_000) });
    if (!response.ok) throw new Error("Price lookup failed");
    const raw = await response.text();
    if (raw.length > 32 * 1024 * 1024) throw new Error("Price catalog is too large");
    const document = JSON.parse(raw);
    const parsed = parsePrices(document);
    if (!parsed.size) throw new Error("Price catalog has no valid rates");
    prices = parsed;
    pricing = { status: "fresh", source: PRICES_URL, fetchedAt: new Date().toISOString() };
    await saveJson(pricesPath, { fetchedAt: pricing.fetchedAt, document });
  } catch {
    pricing.status = prices.size ? "cached" : "unavailable";
  }
}

async function handle(operation, payload) {
  overrides ??= validatePrices(await readJson(overridesPath) ?? {});
  if (operation === "prices") return overrides;
  if (operation === "save-prices") {
    const next = validatePrices(payload);
    await saveJson(overridesPath, next);
    overrides = next;
    return overrides;
  }
  if (operation !== "summary") throw new Error("Unknown usage operation");
  const window = validateWindow(payload);
  const [history] = await Promise.all([
    scanHistories(workerData.sources, cache),
    loadPrices(payload.refresh === true),
  ]);
  const resolved = await resolveT3Tiers(history.records, workerData.t3Database);
  return { ...summarize(resolved.records, { ...payload, ...window }, prices, overrides), sources: history.sources, pricing, t3Tiers: resolved.t3Tiers };
}

let queue = Promise.resolve();
parentPort.on("message", ({ id, operation, payload }) => {
  queue = queue.then(async () => {
    try { parentPort.postMessage({ id, value: await handle(operation, payload) }); }
    catch { parentPort.postMessage({ id, error: "Usage data could not be read. Check the selected period, time zone and local history permissions." }); }
  });
});
