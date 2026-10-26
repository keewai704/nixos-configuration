const percent = (value) => typeof value === "number" && Number.isFinite(value) ? Math.min(100, Math.max(0, value)) : null;
const iso = (value) => {
  const at = typeof value === "number" ? value * 1_000 : typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isFinite(at) && at > 0 && at < 8.64e15 ? new Date(at).toISOString() : null;
};

function window(id, label, used, resetsAt, durationMins, scoped = false) {
  const normalized = percent(used);
  if (normalized === null) return null;
  return { id, label, usedPercent: normalized, remainingPercent: 100 - normalized, resetsAt: iso(resetsAt), durationMins, scoped };
}

export function normalizeLimits(provider, raw, now = Date.now()) {
  const windows = [];
  if (provider === "claude") {
    if (!raw.rate_limits_available || !raw.rate_limits) return { provider, plan: raw.plan, status: "unsupported", windows: [] };
    const limits = raw.rate_limits;
    for (const [id, label, duration] of [["five_hour", "session", 300], ["seven_day", "weekly", 10_080]]) {
      const value = limits[id];
      if (value) windows.push(window(id, label, value.utilization, value.resets_at, duration));
    }
    for (const value of limits.model_scoped ?? []) {
      if (typeof value.display_name === "string") windows.push(window(`model:${value.display_name}`, value.display_name, value.utilization, value.resets_at, 10_080, true));
    }
    const spend = limits.spend;
    const used = spend?.used;
    const cap = spend?.limit;
    if (spend?.enabled && typeof used?.currency === "string" && used.currency.length > 0 && used.currency === cap?.currency && used.exponent === cap?.exponent
      && Number.isFinite(used.amount_minor) && used.amount_minor >= 0 && cap?.amount_minor > 0) {
      windows.push(window("spend", "monthlySpend", used.amount_minor * 100 / cap.amount_minor, null, 43_200));
    } else if (limits.extra_usage?.is_enabled) {
      const extra = limits.extra_usage;
      windows.push(window("spend", "monthlySpend", extra.monthly_limit > 0 ? extra.used_credits * 100 / extra.monthly_limit : extra.utilization, null, 43_200));
    }
  } else {
    const groups = new Map(raw.rateLimits ? [[raw.rateLimits.limitId ?? "codex", raw.rateLimits]] : []);
    for (const [id, value] of Object.entries(raw.rateLimitsByLimitId ?? {})) groups.set(id, value);
    for (const [id, group] of groups) {
      if (!group) continue;
      const scoped = id !== "codex";
      const monthly = ["free", "go"].includes(group.planType ?? raw.plan);
      for (const [position, fallback] of [["primary", monthly ? 43_200 : 300], ["secondary", 10_080]]) {
        const value = group[position];
        if (!value) continue;
        const duration = Number.isFinite(value.windowDurationMins) ? value.windowDurationMins : fallback;
        const label = duration >= 43_200 ? "monthly" : duration >= 10_080 ? "weekly" : "session";
        windows.push(window(`${id}:${position}`, scoped ? `${id} · ${label}` : label, value.usedPercent, value.resetsAt, duration, scoped));
      }
      if (group.individualLimit) windows.push(window(`${id}:individual`, "monthlyCredit", 100 - group.individualLimit.remainingPercent, group.individualLimit.resetsAt, 43_200, scoped));
    }
  }
  const valid = windows.filter(Boolean);
  const exhaustedWeek = valid.find((value) => !value.scoped && value.durationMins === 10_080 && value.remainingPercent === 0);
  if (exhaustedWeek) for (const value of valid) {
    if (value.scoped || value.durationMins !== 300) continue;
    value.rawRemainingPercent = value.remainingPercent;
    value.remainingPercent = 0;
    const weeklyAt = Date.parse(exhaustedWeek.resetsAt);
    const sessionAt = Date.parse(value.resetsAt);
    if (weeklyAt > now && (value.rawRemainingPercent > 0 || sessionAt > now)) {
      value.nextAvailableAt = new Date(value.rawRemainingPercent > 0 ? weeklyAt : Math.max(weeklyAt, sessionAt)).toISOString();
    }
  }
  return {
    provider, plan: typeof raw.plan === "string" ? raw.plan : null,
    status: valid.length ? "ok" : "unavailable", windows: valid,
    resetCredits: Number.isSafeInteger(raw.resetCredits) && raw.resetCredits >= 0 ? raw.resetCredits : null,
  };
}
