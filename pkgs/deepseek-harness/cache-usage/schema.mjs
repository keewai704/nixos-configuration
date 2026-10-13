export function createScopedUsageSchemas(z) {
  const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
  const tokens = count.nullable();
  const bucket = z.object({
    totalTokens: tokens,
    uncachedInputTokens: tokens,
    outputTokens: tokens,
    cacheReadTokens: tokens,
    cacheWriteTokens: tokens,
    cacheEligibleInputTokens: tokens,
    cacheEligibleReadTokens: tokens,
    calls: count,
    measuredCalls: count,
    cacheMeasuredCalls: count,
    failedCalls: count,
    missingInput: count,
    missingOutput: count,
    missingCacheRead: count,
    missingCacheWrite: count,
  }).strict();
  const fields = {
    sessionId: z.string(),
    inheritedEvents: count,
    ordinary: bucket,
    summaries: bucket,
    unknownCompactions: count,
    failedCompactions: count,
    legacySummaries: count,
  };
  return {
    view: z.object({ version: z.literal(1), ...fields }).strict(),
    state: z.object({
      ...fields,
      lastSeq: z.number().int().min(-1).max(Number.MAX_SAFE_INTEGER),
      provider: z.string().nullable(),
      attempt: z.object({ turn: count, step: count, bucket }).strict().nullable(),
      retryKey: z.string().nullable(),
      compaction: z.object({
        id: z.string(), recordedCalls: count, summarySeen: z.boolean(), ended: z.boolean(),
      }).strict().nullable(),
    }).strict(),
  };
}
