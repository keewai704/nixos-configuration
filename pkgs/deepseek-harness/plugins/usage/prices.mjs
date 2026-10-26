export const PRICES_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";

const amount = (value) => typeof value === "number" && Number.isFinite(value) && value >= 0;
const fields = ["input", "output", "cacheRead", "cacheWrite"];
const ambiguousAliases = new Set(["default", "auto", "opus", "sonnet", "haiku", "fable"]);

function rates(raw, suffix = "", standard) {
  const input = raw[`input_cost_per_token${suffix}`];
  const output = raw[`output_cost_per_token${suffix}`];
  if (!amount(input) || !amount(output)) return null;
  const cacheRate = (key, field) => {
    const value = raw[`${key}${suffix}`];
    return amount(value) ? value : standard?.input > 0 ? standard[field] * input / standard.input : input;
  };
  return {
    input, output,
    cacheRead: cacheRate("cache_read_input_token_cost", "cacheRead"),
    cacheWrite: cacheRate("cache_creation_input_token_cost", "cacheWrite"),
  };
}

export function parsePrices(document) {
  const table = new Map();
  if (!document || typeof document !== "object" || Array.isArray(document)) return table;
  for (const [name, raw] of Object.entries(document)) {
    if (!raw || typeof raw !== "object") continue;
    const standard = rates(raw);
    if (!standard) continue;
    const multiplier = raw.provider_specific_entry?.fast;
    table.set(name.trim().toLowerCase(), {
      ...standard,
      fast: amount(multiplier) && multiplier > 0
        ? Object.fromEntries(fields.map((field) => [field, standard[field] * multiplier]))
        : rates(raw, "_priority", standard),
      ultrafast: rates(raw, "_ultrafast", standard),
    });
  }
  const aliases = new Map();
  for (const [name, price] of table) {
    const bare = name.slice(name.lastIndexOf("/") + 1);
    if (table.has(bare)) continue;
    if (!aliases.has(bare)) aliases.set(bare, price);
    else if (JSON.stringify(aliases.get(bare)) !== JSON.stringify(price)) aliases.set(bare, null);
  }
  for (const [name, price] of aliases) if (price) table.set(name, price);
  return table;
}

export function validatePrices(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid model prices");
  for (const [model, price] of Object.entries(value)) {
    if (!model.trim() || model.length > 256 || !price || typeof price !== "object" || Array.isArray(price)
      || !amount(price.input) || !amount(price.output)
      || fields.slice(2).some((field) => price[field] !== undefined && !amount(price[field]))
      || Object.keys(price).some((field) => !fields.includes(field))) throw new Error("Invalid model prices");
  }
  return value;
}

export function priceRecord(record, table, overrides = {}) {
  const override = Object.hasOwn(overrides, record.model) ? overrides[record.model] : undefined;
  const key = record.model.trim().toLowerCase().replace(/\[.*$/, "");
  const automatic = ambiguousAliases.has(key) ? undefined : table.get(key);
  const price = override ? {
    input: override.input / 1_000_000, output: override.output / 1_000_000,
    cacheRead: (override.cacheRead ?? override.input) / 1_000_000,
    cacheWrite: (override.cacheWrite ?? override.input) / 1_000_000,
  } : automatic;
  const reported = !override && amount(record.reportedCost) ? record.reportedCost : null;
  if (!price) return { cost: reported, categories: null, premium: 0, savings: 0, basis: reported === null ? "unpriced" : "reported" };
  const chosen = record.speed !== "standard" && !override ? price[record.speed] ?? price : price;
  const categories = Object.fromEntries(fields.map((field) => [field, record.totals[field] * chosen[field]]));
  const estimated = Object.values(categories).reduce((sum, value) => sum + value, 0);
  const cost = reported ?? estimated;
  const scale = estimated > 0 ? cost / estimated : 1;
  return {
    cost, categories: estimated > 0 || cost === 0 ? Object.fromEntries(fields.map((field) => [field, categories[field] * scale])) : null,
    premium: record.speed === "standard" ? 0 : (estimated - fields.reduce((sum, field) => sum + record.totals[field] * price[field], 0)) * scale,
    savings: record.totals.cacheRead * (chosen.input - chosen.cacheRead),
    basis: override ? "custom" : reported === null ? "estimated" : "reported",
  };
}
