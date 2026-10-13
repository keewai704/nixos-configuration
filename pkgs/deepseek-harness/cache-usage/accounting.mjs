export const tokenFields = [
  'totalTokens', 'uncachedInputTokens', 'outputTokens', 'cacheReadTokens',
  'cacheWriteTokens', 'cacheEligibleInputTokens', 'cacheEligibleReadTokens',
];

export const countFields = [
  'calls', 'measuredCalls', 'cacheMeasuredCalls', 'failedCalls',
  'missingInput', 'missingOutput', 'missingCacheRead', 'missingCacheWrite',
];

export function emptyUsageBucket() {
  return Object.fromEntries([...tokenFields, ...countFields].map(key => [key, 0]));
}

export function isTokenCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

export function addTokenCounts(...values) {
  if (!values.every(isTokenCount)) return null;
  const sum = values.reduce((total, value) => total + value, 0);
  return isTokenCount(sum) ? sum : null;
}

export function combineUsageBuckets(buckets) {
  const result = emptyUsageBucket();
  for (const bucket of buckets) {
    for (const key of tokenFields) result[key] = addTokenCounts(result[key], bucket[key]);
    for (const key of countFields) result[key] += bucket[key];
  }
  return result;
}

export function usageBucket(sample, failed = false, provider = null) {
  const result = emptyUsageBucket();
  result.calls = 1;
  result.failedCalls = Number(failed);
  const usage = sample && typeof sample === 'object' ? { ...sample } : {};
  const requiredKnown = isTokenCount(usage.inputTokens) && isTokenCount(usage.outputTokens);
  const codexNoWrite = provider === 'codex' && requiredKnown && isTokenCount(usage.cacheReadTokens);
  const withoutWrite = addTokenCounts(usage.inputTokens, usage.outputTokens, usage.cacheReadTokens ?? 0);
  const provenZeroWrite = requiredKnown && isTokenCount(usage.totalTokens)
    && withoutWrite !== null && withoutWrite === usage.totalTokens;
  if (usage.cacheWriteTokens === undefined && (codexNoWrite || provenZeroWrite)) usage.cacheWriteTokens = 0;
  const fields = [
    ['inputTokens', 'uncachedInputTokens', 'missingInput'],
    ['outputTokens', 'outputTokens', 'missingOutput'],
    ['cacheReadTokens', 'cacheReadTokens', 'missingCacheRead'],
    ['cacheWriteTokens', 'cacheWriteTokens', 'missingCacheWrite'],
  ];
  const invalid = fields.some(([source]) => usage[source] !== undefined && !isTokenCount(usage[source]))
    || (usage.totalTokens !== undefined && !isTokenCount(usage.totalTokens))
    || (usage.reasoningTokens !== undefined && (!isTokenCount(usage.reasoningTokens)
      || !isTokenCount(usage.outputTokens) || usage.reasoningTokens > usage.outputTokens));
  const knownPrompt = addTokenCounts(usage.inputTokens, usage.cacheReadTokens ?? 0, usage.cacheWriteTokens ?? 0);
  const allPrompt = ['inputTokens', 'cacheReadTokens', 'cacheWriteTokens'].every(key => isTokenCount(usage[key]));
  const exactTotal = usage.totalTokens ?? (allPrompt ? addTokenCounts(knownPrompt, usage.outputTokens) : null);
  const prompt = isTokenCount(exactTotal) && isTokenCount(usage.outputTokens) ? exactTotal - usage.outputTokens : null;
  const contradictory = prompt !== null && (!isTokenCount(prompt)
    || (knownPrompt !== null && (prompt < knownPrompt || (allPrompt && prompt !== knownPrompt))));
  for (const [source, target, missing] of fields) {
    if (!invalid && !contradictory && isTokenCount(usage[source])) result[target] = usage[source];
    else result[missing] = 1;
  }
  if (invalid || contradictory || knownPrompt === null) return result;
  if (isTokenCount(exactTotal) && isTokenCount(usage.inputTokens) && isTokenCount(usage.outputTokens)) {
    result.measuredCalls = 1;
    result.totalTokens = exactTotal;
  }
  if (isTokenCount(prompt) && isTokenCount(usage.cacheReadTokens) && usage.cacheReadTokens <= prompt) {
    result.cacheMeasuredCalls = 1;
    result.cacheEligibleInputTokens = prompt;
    result.cacheEligibleReadTokens = usage.cacheReadTokens;
  }
  return result;
}

export function createUsageState(header, inheritedEventCount = 0) {
  return {
    sessionId: header.id,
    inheritedEvents: inheritedEventCount,
    lastSeq: -1,
    provider: null,
    ordinary: emptyUsageBucket(),
    summaries: emptyUsageBucket(),
    unknownCompactions: 0,
    failedCompactions: 0,
    legacySummaries: 0,
    attempt: null,
    retryKey: null,
    compaction: null,
  };
}

function lastUsage(stream) {
  if (!Array.isArray(stream)) return undefined;
  for (let index = stream.length - 1; index >= 0; index--) {
    const record = stream[index];
    if (record?.type === 'chunk' && record.chunk?.type === 'usage') return record.chunk.usage;
  }
  return undefined;
}

function replaceBucket(total, previous, next) {
  if (previous === null) return combineUsageBuckets([total, next]);
  const result = {};
  for (const key of tokenFields) {
    const value = total[key] === null ? null : total[key] - previous[key] + next[key];
    result[key] = isTokenCount(value) ? value : null;
  }
  for (const key of countFields) result[key] = total[key] - previous[key] + next[key];
  return result;
}

function settleOrdinary(state, data, sample, failed) {
  const provider = data.message?.source?.provider ?? state.provider;
  const bucket = usageBucket(sample, failed, provider);
  return {
    ...state,
    ordinary: combineUsageBuckets([state.ordinary, bucket]),
    attempt: { turn: data.turn, step: data.step, bucket },
  };
}

export function applyUsageEvent(state, event) {
  if (!isTokenCount(event.seq) || event.seq <= state.lastSeq) return state;
  const next = { ...state, lastSeq: event.seq };
  const data = event.data ?? {};
  if (event.type === 'request/header') {
    const provider = data.header?.config?.provider;
    return { ...next, provider: typeof provider === 'string' ? provider : null };
  }
  if (event.seq < state.inheritedEvents) return state;
  switch (event.type) {
    case 'assistant/message':
    case 'assistant/attempt':
      return settleOrdinary(next, data, data.usage ?? lastUsage(data.stream),
        event.type === 'assistant/attempt' || data.interrupted === true);
    case 'step/start':
      return { ...next, attempt: null, retryKey: null };
    case 'llm/retry': {
      const same = next.attempt?.turn === data.turn && next.attempt.step === data.step;
      if (!same) return settleOrdinary(next, data, undefined, true);
      if (next.attempt.bucket.failedCalls !== 0) return next;
      const bucket = { ...next.attempt.bucket, failedCalls: 1 };
      return { ...next, ordinary: replaceBucket(next.ordinary, next.attempt.bucket, bucket), attempt: { ...next.attempt, bucket } };
    }
    case 'llm/retry-started': {
      const retryKey = JSON.stringify([data.turn, data.step, data.retryId, data.retry]);
      return retryKey === next.retryKey ? next : { ...next, attempt: null, retryKey };
    }
    case 'compaction/start':
      return { ...next, compaction: { id: data.compactionId, recordedCalls: 0, summarySeen: false, ended: false } };
    case 'plugin:cache-efficiency/compaction-usage': {
      if (event.ignorable !== true || typeof data.compactionId !== 'string' || data.compactionId.length === 0
        || typeof data.provider !== 'string' || typeof data.model !== 'string'
        || (data.outcome !== 'completed' && data.outcome !== 'error')) return state;
      const compaction = next.compaction?.id === data.compactionId ? next.compaction
        : { id: data.compactionId, recordedCalls: 0, summarySeen: false, ended: false };
      return {
        ...next,
        summaries: combineUsageBuckets([next.summaries, usageBucket(data.usage, data.outcome === 'error', data.provider)]),
        compaction: { ...compaction, recordedCalls: compaction.recordedCalls + 1 },
      };
    }
    case 'compaction/summary': {
      const compaction = next.compaction?.id === data.compactionId ? next.compaction
        : { id: data.compactionId, recordedCalls: 0, summarySeen: false, ended: false };
      if (compaction.summarySeen) return next;
      const recorded = compaction.recordedCalls > 0;
      return {
        ...next,
        summaries: recorded ? next.summaries : combineUsageBuckets([next.summaries, usageBucket(data.usage, false, data.provider)]),
        legacySummaries: next.legacySummaries + Number(!recorded),
        compaction: { ...compaction, summarySeen: true },
      };
    }
    case 'compaction/end': {
      const compaction = next.compaction?.id === data.compactionId ? next.compaction
        : { id: data.compactionId, recordedCalls: 0, summarySeen: false, ended: false };
      if (compaction.ended) return next;
      const failed = typeof data.error === 'string';
      return {
        ...next,
        failedCompactions: next.failedCompactions + Number(failed),
        unknownCompactions: next.unknownCompactions + Number(failed && compaction.recordedCalls === 0 && !compaction.summarySeen),
        compaction: { ...compaction, ended: true },
      };
    }
    default:
      return state;
  }
}

export function usageView(state) {
  return {
    version: 1,
    sessionId: state.sessionId,
    inheritedEvents: state.inheritedEvents,
    ordinary: state.ordinary,
    summaries: state.summaries,
    unknownCompactions: state.unknownCompactions,
    failedCompactions: state.failedCompactions,
    legacySummaries: state.legacySummaries,
  };
}
