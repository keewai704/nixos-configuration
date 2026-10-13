import { combineUsageBuckets, emptyUsageBucket, isTokenCount } from './accounting.mjs';

export function collectScopedUsage(sessionId, ownUsage, ownCatalog, sessions) {
  const visited = new Set();
  const queue = [{ id: sessionId, parentId: null, mode: 'root' }];
  const rows = [];
  const edges = [];
  const missing = [];
  const refresh = [];
  let ordinary = emptyUsageBucket();
  let summaries = emptyUsageBucket();
  const childBuckets = [];
  let unknownCompactions = 0;
  let failedCompactions = 0;
  let legacySummaries = 0;
  for (let index = 0; index < queue.length; index++) {
    const node = queue[index];
    if (visited.has(node.id)) continue;
    visited.add(node.id);
    const snapshot = sessions?.projectionsBySession?.[node.id];
    const row = sessions?.byId?.[node.id];
    const values = snapshot?.values ?? row?.projectionValues ?? {};
    const usage = node.parentId === null ? ownUsage : values.scopedUsage;
    const catalog = node.parentId === null ? ownCatalog : values.subagentCatalog;
    const external = node.mode === 'external';
    const ready = node.parentId === null || snapshot?.state === 'ready' || row?.running === true;
    const valid = !external && usage?.version === 1 && usage.sessionId === node.id;
    const rowMissing = external ? 'external' : !valid ? 'unavailable'
      : snapshot?.state === 'error' ? 'error'
      : snapshot?.state === 'migration-required' ? 'migration-required'
      : !ready ? 'unverified' : null;
    if (rowMissing !== null) missing.push({ id: node.id, reason: rowMissing });
    if (!external && snapshot?.state !== 'loading' && snapshot?.state !== 'ready'
      && snapshot?.state !== 'migration-required' && snapshot?.state !== 'error'
      && (node.parentId !== null || !valid || !Array.isArray(catalog))) refresh.push(node.id);
    if (valid) {
      const total = combineUsageBuckets([usage.ordinary, usage.summaries]);
      if (node.parentId === null) {
        ordinary = usage.ordinary;
        summaries = usage.summaries;
      } else childBuckets.push(total);
      unknownCompactions += usage.unknownCompactions;
      failedCompactions += usage.failedCompactions;
      legacySummaries += usage.legacySummaries;
      rows.push({ ...node, usage, total, status: rowMissing, label: row?.displayTitle ?? node.label ?? node.id });
    }
    if (external) continue;
    if (!Array.isArray(catalog)) {
      if (rowMissing === null) missing.push({ id: node.id, reason: 'catalog-unavailable' });
      continue;
    }
    for (const child of catalog) {
      if (typeof child.id !== 'string' || child.id.length === 0) continue;
      edges.push({ parentId: node.id, id: child.id });
      if (!visited.has(child.id)) queue.push({ ...child, parentId: node.id });
    }
  }
  const children = combineUsageBuckets(childBuckets);
  const overall = combineUsageBuckets([ordinary, summaries, children]);
  return {
    ordinary, summaries, children, overall, rows, edges, missing, refresh,
    unknownCompactions, failedCompactions, legacySummaries,
    childSessions: visited.size - 1,
    measuredChildSessions: rows.filter(row => row.parentId !== null).length,
    partial: missing.length > 0 || unknownCompactions > 0 || overall.measuredCalls < overall.calls,
  };
}

export function scopedUsagePresentation(rollup, formatPercent) {
  const bucket = rollup.overall;
  const cacheValid = isTokenCount(bucket.cacheEligibleReadTokens)
    && isTokenCount(bucket.cacheEligibleInputTokens) && bucket.cacheEligibleInputTokens > 0;
  const cachePercent = cacheValid ? formatPercent(bucket.cacheEligibleReadTokens, bucket.cacheEligibleInputTokens, 1) : null;
  return {
    cachePercent,
    cachePartial: rollup.missing.length > 0 || rollup.unknownCompactions > 0
      || bucket.cacheMeasuredCalls < bucket.calls,
    total: isTokenCount(bucket.totalTokens) ? bucket.totalTokens : null,
    totalPartial: rollup.partial,
  };
}
