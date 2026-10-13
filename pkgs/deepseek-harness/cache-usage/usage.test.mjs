import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { addTokenCounts, applyUsageEvent, combineUsageBuckets, createUsageState, usageBucket, usageView } from './accounting.mjs';
import { collectScopedUsage, scopedUsagePresentation } from './rollup.mjs';

const reported = (inputTokens = 10, cacheReadTokens = 90, outputTokens = 5, cacheWriteTokens = 0) => ({
  inputTokens, cacheReadTokens, outputTokens, cacheWriteTokens,
  totalTokens: inputTokens + cacheReadTokens + outputTokens + cacheWriteTokens,
});
const event = (seq, type, data = {}, rest = {}) => ({ seq, type, data, ...rest });
const message = (seq, usage = reported(), step = seq) => event(seq, 'assistant/message', { turn: 1, step, usage, stream: [] });
const fold = (events, id = 'root', inherited = 0) => usageView(events.reduce(applyUsageEvent, createUsageState({ id }, inherited)));
const values = (id, ordinary, summaries = [], subagentCatalog = []) => ({
  scopedUsage: fold([...ordinary, ...summaries], id), subagentCatalog,
});
const sessions = entries => ({
  byId: {},
  projectionsBySession: Object.fromEntries(entries.map(([id, value, state = 'ready']) => [id, { values: value, state }])),
});
const percent = (read, input) => String(Math.round(read / input * 1000) / 10);


test('provider usage stays disjoint and reasoning is not counted twice', () => {
  const bucket = usageBucket({ ...reported(20, 70, 10, 10), reasoningTokens: 8 });
  assert.equal(bucket.totalTokens, 110);
  assert.equal(bucket.cacheEligibleInputTokens, 100);
  assert.equal(bucket.cacheEligibleReadTokens, 70);
  assert.equal(bucket.measuredCalls, 1);
  assert.equal(bucket.cacheMeasuredCalls, 1);
});

test('unknown usage and omitted cache buckets are not reported as zero', () => {
  const unknown = usageBucket(undefined, true);
  assert.equal(unknown.calls, 1);
  assert.equal(unknown.measuredCalls, 0);
  assert.equal(unknown.cacheMeasuredCalls, 0);
  assert.equal(unknown.failedCalls, 1);
  assert.equal(unknown.missingCacheRead, 1);
  const omitted = usageBucket({ inputTokens: 20, outputTokens: 10 });
  assert.equal(omitted.measuredCalls, 0);
  assert.equal(omitted.cacheMeasuredCalls, 0);
  assert.equal(omitted.missingCacheWrite, 1);
  const exactTotal = usageBucket({ inputTokens: 20, cacheReadTokens: 80, outputTokens: 10, totalTokens: 110 });
  assert.equal(exactTotal.measuredCalls, 1);
  assert.equal(exactTotal.cacheMeasuredCalls, 1);
  assert.equal(exactTotal.missingCacheWrite, 1);
  assert.equal(exactTotal.cacheEligibleInputTokens, 100);
  assert.equal(usageBucket(reported(0, 0, 0)).measuredCalls, 1);
});

test('invalid, contradictory, and overflowing provider usage remains unknown', () => {
  for (const sample of [
    { ...reported(), inputTokens: -1 },
    { ...reported(), cacheReadTokens: NaN },
    { ...reported(), cacheWriteTokens: 0.5 },
    { ...reported(), reasoningTokens: 6 },
    { ...reported(), totalTokens: 104 },
    { inputTokens: Number.MAX_SAFE_INTEGER, outputTokens: 2, cacheReadTokens: 3, cacheWriteTokens: 0 },
  ]) {
    assert.equal(usageBucket(sample).measuredCalls, 0);
    assert.equal(usageBucket(sample).cacheMeasuredCalls, 0);
  }
  assert.equal(addTokenCounts(Number.MAX_SAFE_INTEGER, 1), null);
  const large = usageBucket(reported(Number.MAX_SAFE_INTEGER, 0, 0));
  assert.equal(combineUsageBuckets([large, usageBucket(reported(1, 0, 0))]).totalTokens, null);
});

test('unique durable settlements count once, final sample wins, retry chains add every call', () => {
  const first = event(1, 'assistant/attempt', { turn: 1, step: 1, stream: [
    { type: 'chunk', chunk: { type: 'usage', usage: reported(1, 1, 1) } },
    { type: 'chunk', chunk: { type: 'usage', usage: reported(10, 90, 5) } },
  ] });
  const result = fold([
    event(0, 'step/start', { turn: 1, step: 1 }), first, first,
    event(2, 'llm/retry', { turn: 1, step: 1, retryId: 'chain', retry: 1 }),
    event(3, 'llm/retry-started', { turn: 1, step: 1, retryId: 'chain', retry: 1 }),
    event(4, 'assistant/attempt', first.data),
    event(5, 'llm/retry', { turn: 1, step: 1, retryId: 'chain', retry: 2 }),
    event(6, 'llm/retry-started', { turn: 1, step: 1, retryId: 'chain', retry: 2 }),
    message(7, reported(20, 80, 10), 1),
  ]);
  assert.equal(result.ordinary.calls, 3);
  assert.equal(result.ordinary.totalTokens, 320);
  assert.equal(result.ordinary.failedCalls, 2);
});

test('implicit compaction and image-offload recovery retain same-step attempts without retry events', () => {
  const result = fold([
    event(0, 'assistant/attempt', { turn: 1, step: 1, stream: [] }),
    event(1, 'compaction/start', { compactionId: 'c' }),
    event(2, 'compaction/summary', { compactionId: 'c', usage: reported(80, 20) }),
    event(3, 'compaction/end', { compactionId: 'c' }),
    event(4, 'assistant/attempt', { turn: 1, step: 1, stream: [] }),
    event(5, 'image/offload', { targets: [] }),
    message(6, reported(), 1),
    message(6, reported(), 1),
  ]);
  assert.equal(result.ordinary.calls, 3);
  assert.equal(result.ordinary.measuredCalls, 1);
  assert.equal(result.ordinary.failedCalls, 2);
  assert.equal(result.ordinary.totalTokens, 105);
  assert.equal(result.summaries.calls, 1);
});

test('usage missing from failed retries stays unknown beside successful calls', () => {
  const result = fold([
    event(0, 'llm/retry', { turn: 1, step: 1 }),
    event(1, 'llm/retry-started', { turn: 1, step: 1, retryId: 'retry-1' }),
    message(2, reported(), 1),
  ]);
  assert.equal(result.ordinary.calls, 2);
  assert.equal(result.ordinary.measuredCalls, 1);
  assert.equal(result.ordinary.failedCalls, 1);
  assert.equal(result.ordinary.totalTokens, 105);
});

test('current usage counts top-level records only, excluding embedded logs and fork seed', () => {
  const result = fold([
    message(0, reported(1000, 9000)),
    event(1, 'session/end-seed', { inherited: true }),
    message(2),
    event(3, 'user/message', { embeddedLog: [message(0)], snapshot: { usage: reported(1000, 9000) } }),
    event(4, 'compaction/summary', { compactionId: 'c', usage: reported(80, 20), rawOutput: [message(0)] }),
    event(5, 'session/end-seed', {}),
    message(6),
  ], 'child', 2);
  assert.equal(result.sessionId, 'child');
  assert.equal(result.inheritedEvents, 2);
  assert.equal(result.ordinary.calls, 2);
  assert.equal(result.ordinary.totalTokens, 210);
  assert.equal(result.summaries.calls, 1);
  assert.equal(result.summaries.totalTokens, 105);
});

test('summary attempt records include retries, deduplicate legacy summary, and preserve errors', () => {
  const usageRecord = (seq, usage, outcome) => event(seq, 'plugin:cache-efficiency/compaction-usage', {
    compactionId: 'c', provider: 'provider', model: 'model', usage, outcome,
  }, { ignorable: true });
  const result = fold([
    event(0, 'compaction/start', { compactionId: 'c' }),
    usageRecord(1, undefined, 'error'),
    usageRecord(2, reported(80, 20), 'completed'),
    usageRecord(2, reported(80, 20), 'completed'),
    event(3, 'compaction/summary', { compactionId: 'c', usage: reported(80, 20) }),
    event(4, 'compaction/end', { compactionId: 'c' }),
    event(5, 'compaction/start', { compactionId: 'failed-legacy' }),
    event(6, 'compaction/end', { compactionId: 'failed-legacy', error: 'failed before usage' }),
    event(7, 'compaction/end', { compactionId: 'failed-legacy', error: 'failed before usage' }),
  ]);
  assert.equal(result.summaries.calls, 2);
  assert.equal(result.summaries.measuredCalls, 1);
  assert.equal(result.summaries.failedCalls, 1);
  assert.equal(result.summaries.totalTokens, 105);
  assert.equal(result.legacySummaries, 0);
  assert.equal(result.unknownCompactions, 1);
  assert.equal(result.failedCompactions, 1);
});

test('rejected completed summaries are counted even when compaction never commits', () => {
  const result = fold([
    event(0, 'compaction/start', { compactionId: 'c' }),
    event(1, 'plugin:cache-efficiency/compaction-usage', {
      compactionId: 'c', provider: 'p', model: 'm', usage: reported(), outcome: 'completed',
    }, { ignorable: true }),
    event(2, 'compaction/end', { compactionId: 'c', error: 'not smaller' }),
  ]);
  assert.equal(result.summaries.calls, 1);
  assert.equal(result.summaries.measuredCalls, 1);
  assert.equal(result.failedCompactions, 1);
  assert.equal(result.unknownCompactions, 0);
});

test('malformed or non-ignorable plugin records do not affect accounting', () => {
  for (const [data, ignorable] of [
    [{ compactionId: 'c', provider: 'p', model: 'm', outcome: 'completed' }, false],
    [{ compactionId: 'c', provider: 'p', model: 'm', outcome: 'other' }, true],
    [{ provider: 'p', model: 'm', outcome: 'error' }, true],
    [null, true],
  ]) assert.equal(fold([event(0, 'plugin:cache-efficiency/compaction-usage', data, { ignorable })]).summaries.calls, 0);
});

test('nested and repeated child identity is counted once with cycles bounded', () => {
  const root = values('root', [message(0)], [], [{ id: 'child' }, { id: 'child' }]);
  const child = values('child', [message(0, reported(80, 20))], [], [{ id: 'nested' }, { id: 'root' }]);
  const nested = values('nested', [message(0, reported(50, 50))], [], [{ id: 'child' }]);
  const result = collectScopedUsage('root', root.scopedUsage, root.subagentCatalog, sessions([
    ['child', child], ['nested', nested], ['unrelated', values('unrelated', [message(0)])],
  ]));
  assert.equal(result.childSessions, 2);
  assert.equal(result.measuredChildSessions, 2);
  assert.equal(result.children.calls, 2);
  assert.equal(result.overall.calls, 3);
  assert.equal(result.overall.totalTokens, 315);
  assert.equal(result.partial, false);
  assert.equal(scopedUsagePresentation(result, percent).cachePercent, '53.3');
});

test('new, external, missing, stale, migration-deferred and wrong-identity children are explicit', () => {
  const root = values('root', [message(0)], [], [
    { id: 'new' }, { id: 'external', mode: 'external' }, { id: 'wrong' },
    { id: 'stale' }, { id: 'old' },
  ]);
  const result = collectScopedUsage('root', root.scopedUsage, root.subagentCatalog, sessions([
    ['wrong', values('someone-else', [message(0)])],
    ['stale', values('stale', [message(0)]), 'idle'],
    ['old', values('old', [message(0)]), 'migration-required'],
  ]));
  assert.equal(result.childSessions, 5);
  assert.equal(result.measuredChildSessions, 2);
  assert.equal(result.missing.length, 5);
  assert.deepEqual(result.refresh.sort(), ['new', 'stale']);
  assert.equal(result.partial, true);
  assert.equal(scopedUsagePresentation(result, percent).cachePartial, true);
  const newer = { ...root, subagentCatalog: [...root.subagentCatalog, { id: 'later' }] };
  assert.equal(collectScopedUsage('root', newer.scopedUsage, newer.subagentCatalog, sessions([])).childSessions, 6);
});

test('weighted cache is input-weighted, not average per-call rate or output-inclusive', () => {
  const root = values('root', [message(0, reported(10, 90, 1000))], [
    event(1, 'compaction/summary', { compactionId: 'c', usage: reported(800, 200, 1) }),
  ]);
  const result = collectScopedUsage('root', root.scopedUsage, [], sessions([]));
  const display = scopedUsagePresentation(result, percent);
  assert.equal(display.cachePercent, '26.4');
  assert.equal(display.total, 2101);
  assert.equal(display.cachePartial, false);
});

test('zero denominator and absent measurements never fabricate a percentage', () => {
  const root = values('root', [message(0, reported(0, 0, 7))]);
  assert.equal(scopedUsagePresentation(collectScopedUsage('root', root.scopedUsage, [], sessions([])), percent).cachePercent, null);
  const absent = collectScopedUsage('root', undefined, undefined, sessions([]));
  assert.equal(absent.partial, true);
  assert.equal(scopedUsagePresentation(absent, percent).cachePercent, null);
});

function renderPill(usage, catalog, state, mode = 'detailed') {
  const context = {
    react: { memo: fn => fn, useMemo: fn => fn(), useEffect: () => {} },
    react_jsx_runtime: { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }), Fragment: 'fragment' },
    _deepseek_ai_dsh_client_ui_primitives: { IconDatabaseOutlineRegular: 'icon' },
    stat_dialog_module_css_default: { details: 'details' },
    DialogPill: 'dialog',
    collectScopedUsage, scopedUsagePresentation,
    formatCacheHitPercent: percent, formatTokens: String, exactCount: value => `${value} tok`,
    joined$1: (left, right) => `${left} · ${right}`,
  };
  vm.runInNewContext(`${readFileSync(new URL('./usage-pill.js', import.meta.url), 'utf8')}\nglobalThis.render = UsagePill;`, context);
  return context.render({
    useProjection: key => key === 'scopedUsage' ? usage : catalog,
    usePerformanceUsage: select => select(mode),
    useScopedUsageSessions: select => select(state), scopedUsageSessionId: 'root',
    refreshScopedUsage: async () => {},
    t: (key, args) => key === 'message.turnUsage.count' ? `${args.count} tok` : key,
  });
}

test('actual UsagePill keeps unknown state, partial labels and an accessible compact dialog', () => {
  const missing = renderPill(undefined, undefined, sessions([]));
  const unknownText = JSON.stringify(missing);
  assert.match(unknownText, /Recorded Unknown/);
  assert.match(unknownText, /Cache unknown/);
  assert.match(unknownText, /data-scoped-usage/);
  assert.doesNotMatch(unknownText, /Recorded 0 tok/);
  const root = values('root', [message(0)], [], [{ id: 'missing' }]);
  const partial = renderPill(root.scopedUsage, root.subagentCatalog, sessions([]), 'compact');
  assert.equal(partial.type, 'dialog');
  assert.equal(partial.props.label, 'Measured cache 90%');
  assert.equal(partial.props.children.props['data-usage-partial'], true);
  const text = JSON.stringify(partial);
  assert.match(text, /This session · ordinary/);
  assert.match(text, /This session · summaries/);
  assert.match(text, /Descendants · ordinary \+ summaries/);
  assert.match(text, /Inherited history and embedded snapshots excluded/);
  assert.doesNotMatch(text, /NaN|Infinity/);
});
