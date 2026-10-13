import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';

assert.ok(process.env.DSH_KERNEL_ROOT, 'Set DSH_KERNEL_ROOT to the kernel node_modules/@deepseek-ai directory');
const root = resolve(process.env.DSH_KERNEL_ROOT);
const load = (name) => import(pathToFileURL(resolve(root, name, 'lib/index.js')));
const { Context } = await load('cordis');
const { BasicCompactionEngine } = await import(pathToFileURL(
  process.env.DSH_COMPACTION_MODULE ?? resolve(root, 'dsh-compaction-basic/lib/index.js'),
));
const { Session } = await load('dsh-session');
const { TokenMeter } = await load('dsh-token-meter');
const { ToolResultPruner, PRUNE_MARKER } = await load('dsh-compaction-tool-result-pruner');
const {
  CONTEXT_WINDOW_EXCEEDED_CODE,
  LlmError,
  createAssistantMessage,
  createSystemMessage,
  createToolResultMessage,
  createUserMessage,
} = await load('dsh-llm');

const route = { provider: 'codex', model: 'gpt-6-astra' };
const tools = [{ name: 'read', description: 'Read a local file', parameters: { type: 'object', properties: {} } }];
const text = (value) => [{ type: 'text', text: value }];
const signal = () => new AbortController().signal;

function fixture({ config = {}, callConfig = route, contextWindow = 800000, defaultMaxTokens, stream, pruner = true } = {}) {
  const ctx = new Context();
  const calls = [];
  const resolutions = [];
  ctx.provide('sessionProjections', { register() {} });
  ctx.provide('llm', {
    imageRequestPricing() {},
    fileRequestText() {},
    async resolveModelInfo(provider, model) {
      resolutions.push({ provider, model });
      return {
        provider,
        id: model,
        name: model,
        context: { contextWindow },
        ...(defaultMaxTokens === undefined ? {} : { defaultMaxTokens }),
      };
    },
    async *stream(options) {
      calls.push(options);
      if (stream) {
        yield* stream(options, calls.length);
        return;
      }
      yield { type: 'text-delta', index: 0, text: 'Keep the requested fix and run local tests.' };
      yield { type: 'finish', reason: { kind: 'stop' } };
    },
  });
  new TokenMeter(ctx);
  if (pruner) new ToolResultPruner(ctx);
  const engine = new BasicCompactionEngine(ctx, { auto: false, ...config });
  const session = Session.create('cache-regression-session');
  const append = { surfaceOp: 'append' };
  session.append('system/message', { message: createSystemMessage('Stable system prompt') }, append);
  if (callConfig !== null) session.append('request/header', { header: { config: callConfig, tools }, reason: 'initial' });
  session.append('turn/start', { turn: 1 });
  const agent = { session, options: { ...route, reasoningEffort: 'low' } };
  function user(value) {
    return session.append('user/message', createUserMessage({ content: text(value), source: { kind: 'human' } }), append);
  }
  function history(toolChars = 12000) {
    const first = user('Preserve the implementation details. '.repeat(100));
    session.append('step/start', { turn: 1, step: 1 });
    const call = { type: 'tool-call', id: 'read-call', name: 'read', arguments: '{}' };
    session.append('assistant/message', {
      turn: 1,
      step: 1,
      message: createAssistantMessage({ content: [call], source: route }),
      stream: [],
    }, append);
    const result = session.append('tool/result', {
      turn: 1,
      step: 1,
      message: createToolResultMessage({ callId: call.id, content: text('X'.repeat(toolChars)), isError: false }),
    }, append);
    session.append('step/end', { turn: 1, step: 1 });
    const tail = user('Continue with the tests.');
    return { first, result, tail };
  }
  return { ctx, engine, session, agent, calls, resolutions, user, history };
}

function summaryInput(f) {
  return { messages: f.session.deriveMessages(), tools };
}

function fillPressure(f, totalTokens) {
  const framing = f.ctx.tokenMeter.estimateMessage({ role: 'user', content: text('') });
  const tail = f.ctx.tokenMeter.estimateMessage({ role: 'user', content: text('tail') });
  const contentTokens = totalTokens - f.ctx.tokenMeter.measure(f.session).totalTokens - framing - tail;
  f.user('P'.repeat(contentTokens * 4));
  f.user('tail');
  assert.equal(f.ctx.tokenMeter.measure(f.session).totalTokens, totalTokens);
}

for (const explicit of [false, true]) {
  test(`same-route summary inherits durable controls${explicit ? ' with an explicit matching target' : ''}`, async () => {
    const f = fixture({
      callConfig: { ...route, reasoningEffort: 'max', temperature: 0, maxTokens: 32000, stop: ['##'] },
      config: { maxTokens: 2048, ...(explicit ? { summarizationProvider: route.provider, summarizationModel: route.model } : {}) },
    });
    f.user('Summarize this history.');
    const input = summaryInput(f);
    const before = structuredClone(input);
    const abort = signal();
    const result = await f.engine.summarize(input, f.agent, abort);
    const [request] = f.calls;
    assert.equal(request.reasoningEffort, 'max');
    assert.equal(request.temperature, 0);
    assert.equal(request.maxTokens, 2048);
    assert.equal(Object.hasOwn(request, 'stop'), false);
    assert.equal(Object.hasOwn(request, 'topP'), false);
    assert.equal(request.sessionId, f.session.id);
    assert.equal(request.purpose, 'compaction');
    assert.equal(request.signal, abort);
    assert.deepEqual(request.messages.slice(0, -1), input.messages);
    assert.match(request.messages.at(-1).content[0].text, /compaction engine/);
    assert.deepEqual(request.tools, tools);
    assert.deepEqual(request.toolHistory, f.session.toolHistory());
    assert.deepEqual(input, before);
    assert.equal(result.maxTokens, 2048);
  });
}

for (const target of [{ provider: 'other', model: route.model }, { provider: route.provider, model: 'other' }]) {
  test(`explicit different target ${target.provider}/${target.model} does not inherit controls`, async () => {
    const f = fixture({
      callConfig: { ...route, reasoningEffort: 'max', temperature: 0.3, stop: ['stop'] },
      config: { summarizationProvider: target.provider, summarizationModel: target.model },
    });
    await f.engine.summarize(summaryInput(f), f.agent, signal());
    assert.equal(f.calls[0].provider, target.provider);
    assert.equal(f.calls[0].model, target.model);
    for (const key of ['reasoningEffort', 'temperature', 'stop']) assert.equal(Object.hasOwn(f.calls[0], key), false);
  });
}

test('summary without a durable header uses agent route without inventing controls', async () => {
  const f = fixture({ callConfig: null });
  await f.engine.summarize(summaryInput(f), f.agent, signal());
  assert.equal(f.calls[0].provider, route.provider);
  assert.equal(f.calls[0].model, route.model);
  assert.equal(Object.hasOwn(f.calls[0], 'reasoningEffort'), false);
  assert.equal(Object.hasOwn(f.calls[0], 'temperature'), false);
});

test('same-route absent controls stay absent', async () => {
  const f = fixture();
  await f.engine.summarize(summaryInput(f), f.agent, signal());
  assert.equal(Object.hasOwn(f.calls[0], 'reasoningEffort'), false);
  assert.equal(Object.hasOwn(f.calls[0], 'temperature'), false);
});

test('pressure compacts the unchanged historical prefix without pre-pruning', async () => {
  const f = fixture({ config: { thresholdRatio: 0.005, retainTokens: 0 } });
  const { tail } = f.history();
  const prefix = f.session.deriveMessages().slice(0, -1);
  const generation = f.session.surface.replaceGeneration;
  const result = await f.engine.compactIfNeeded(f.agent, 'pressure', signal());
  assert.ok(result);
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0].messages.slice(0, -1), prefix);
  assert.equal(f.session.snapshotEvents().filter((event) => event.type === 'compaction/prune').length, 0);
  assert.equal(f.session.surface.replaceGeneration, generation + 1);
  assert.equal(f.session.surface.nodes.at(-1), tail.seq);
  assert.notDeepEqual(f.session.deriveMessages().slice(0, -1), prefix);
});

test('repeated ordinary pre-step hooks do not rewrite tool history below pressure', async () => {
  const f = fixture({ config: { auto: true } });
  f.history();
  const before = f.session.snapshotEvents();
  for (let i = 0; i < 3; i += 1) {
    const result = await f.ctx.waterfall('agent/pre-step', { agent: f.agent, signal: signal() }, () => 'continue');
    assert.equal(result, 'continue');
  }
  assert.deepEqual(f.session.snapshotEvents(), before);
  assert.equal(f.calls.length, 0);
});

test('provider-confirmed overflow keeps emergency pruning and bounded retry', async () => {
  const f = fixture({ config: { auto: true } });
  f.history();
  const failure = { code: CONTEXT_WINDOW_EXCEEDED_CODE, message: 'context is full' };
  const result = await f.ctx.waterfall('agent/request-error', { agent: f.agent, failure, signal: signal() }, () => 'unhandled');
  assert.deepEqual(result, { kind: 'retry' });
  assert.ok(f.session.snapshotEvents().some((event) => event.type === 'compaction/prune'));
  assert.ok(f.calls[0].messages.some((message) => message.content.some((block) => block.text?.includes(PRUNE_MARKER))));
  assert.equal(await f.ctx.waterfall('agent/request-error', { agent: f.agent, failure, signal: signal() }, () => 'unhandled'), 'unhandled');
  assert.equal(f.calls.length, 1);
});

test('failed pressure summary leaves history untouched and overflow recovery available', async () => {
  const f = fixture({
    config: { auto: true, thresholdRatio: 0.005, retainTokens: 0 },
    async *stream(options, attempt) {
      if (attempt === 1) throw new LlmError('summary input too large', CONTEXT_WINDOW_EXCEEDED_CODE);
      yield { type: 'text-delta', index: 0, text: 'A smaller checkpoint.' };
      yield { type: 'finish', reason: { kind: 'stop' } };
    },
  });
  f.history();
  const before = f.session.deriveMessages();
  assert.equal(await f.ctx.waterfall('agent/pre-step', { agent: f.agent, signal: signal() }, () => 'continue'), 'continue');
  assert.deepEqual(f.session.deriveMessages(), before);
  assert.equal(f.session.snapshotEvents().filter((event) => event.type === 'compaction/prune').length, 0);
  assert.equal(f.session.snapshotEvents().filter((event) => event.type === 'compaction/end').length, 1);
  const failure = { code: CONTEXT_WINDOW_EXCEEDED_CODE, message: 'real request overflow' };
  assert.deepEqual(await f.ctx.waterfall('agent/request-error', { agent: f.agent, failure, signal: signal() }, () => 'unhandled'), { kind: 'retry' });
  assert.equal(f.calls.length, 2);
});

test('overflow cancellation cannot prune history', async () => {
  const f = fixture({ config: { auto: true } });
  f.history();
  const before = f.session.snapshotEvents();
  const failure = { code: CONTEXT_WINDOW_EXCEEDED_CODE, message: 'context is full' };
  const aborted = AbortSignal.abort();
  assert.equal(await f.ctx.waterfall('agent/request-error', { agent: f.agent, failure, signal: aborted }, () => 'unhandled'), 'unhandled');
  assert.deepEqual(f.session.snapshotEvents(), before);
});

test('standalone pruner still preserves budgets, rich blocks and tool outcome metadata', () => {
  const f = fixture();
  const { result } = f.history();
  const rich = { type: 'file', attachment: { id: 'attachment', name: 'result.txt' } };
  const blocks = [{ type: 'text', text: '🟢'.repeat(9000) }, rich];
  const pruned = f.ctx.toolResultPruner.pruneContent(blocks);
  assert.equal(pruned.at(-1), rich);
  assert.ok(f.ctx.toolResultPruner.measureContent(pruned) <= f.ctx.toolResultPruner.config.thresholdChars);
  assert.equal(pruned[0].text.startsWith('🟢'.repeat(4096)), true);
  assert.equal(pruned[0].text.endsWith('🟢'.repeat(1024)), true);
  const changed = f.ctx.toolResultPruner.pruneSession(f.session);
  const replacement = f.session.eventAt(changed.pruned[0].replacementSeq);
  assert.equal(replacement.data.message.source.callId, result.data.message.source.callId);
  assert.equal(replacement.data.message.isError, result.data.message.isError);
  assert.deepEqual(replacement.sourceEventSeqs, [result.seq]);
});

for (const model of ['gpt-6-astra', '~account:fixture-account:gpt-6-astra', 'custom-pool', 'future-model']) {
  test(`absolute threshold applies to routed model ${model}`, async () => {
    const f = fixture({ config: { thresholdTokens: 400000, retainTokens: 0 }, callConfig: { ...route, model } });
    fillPressure(f, 399999);
    assert.equal(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()), null);
    const boundary = fixture({ config: { thresholdTokens: 400000, retainTokens: 0 }, callConfig: { ...route, model } });
    fillPressure(boundary, 400000);
    assert.ok(await boundary.engine.compactIfNeeded(boundary.agent, 'pressure', signal()));
    assert.equal(boundary.calls.length, 1);
    assert.equal(boundary.calls[0].model, model);
    assert.deepEqual(boundary.resolutions.at(-1), { ...route, model });
  });
}

test('absolute threshold also covers an unknown provider with advertised capacity', async () => {
  const f = fixture({ config: { thresholdTokens: 4000, retainTokens: 0 }, callConfig: { provider: 'custom-provider', model: 'pool' } });
  f.history();
  assert.ok(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()));
  assert.equal(f.calls[0].provider, 'custom-provider');
});

test('absolute threshold is capped by context minus durable output and headroom', async () => {
  const f = fixture({
    config: { thresholdTokens: 400000, retainTokens: 0, headroomTokens: 1000 },
    callConfig: { ...route, maxTokens: 2000 },
    contextWindow: 7000,
    defaultMaxTokens: 3000,
  });
  f.history();
  assert.ok(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()));
  assert.equal(f.calls.length, 1);
});

test('capacity protection uses the adapter output reservation when the header omits it', async () => {
  const f = fixture({
    config: { thresholdTokens: 400000, retainTokens: 0, headroomTokens: 1000 },
    contextWindow: 7000,
    defaultMaxTokens: 2000,
  });
  f.history();
  assert.ok(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()));
});

test('272k context compacts at the 78464-token budget cap with default retention', async () => {
  for (const pressure of [78463, 78464]) {
    const f = fixture({
      config: { thresholdTokens: 400000 },
      callConfig: { ...route, maxTokens: 128000 },
      contextWindow: 272000,
    });
    f.user('Earlier history. '.repeat(12000));
    fillPressure(f, pressure);
    const result = await f.engine.compactIfNeeded(f.agent, 'pressure', signal());
    assert.equal(result !== null, pressure === 78464);
  }
});

test('existing ratio and defaults remain effective without an absolute threshold', async () => {
  const f = fixture({ config: { thresholdRatio: 0.005, retainTokens: 0 }, pruner: false });
  f.history();
  assert.ok(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()));
  const defaulted = fixture();
  defaulted.history();
  assert.equal(await defaulted.engine.compactIfNeeded(defaulted.agent, 'pressure', signal()), null);
});

test('exact model policy can override the inherited absolute threshold', async () => {
  const f = fixture({ config: {
    thresholdTokens: 400000,
    retainTokens: 0,
    modelPolicies: [{ ...route, thresholdTokens: 4000 }],
  } });
  f.history();
  assert.ok(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()));
});

test('absolute thresholds bypass irrelevant ratio retention checks but retain the concrete guard', async () => {
  const f = fixture({ config: { thresholdTokens: 400000, thresholdRatio: 0.1, retainRatio: 0.2 } });
  assert.equal(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()), null);
  const incompatible = fixture({ config: { thresholdTokens: 4000, retainTokens: 4000 } });
  await assert.rejects(incompatible.engine.compactIfNeeded(incompatible.agent, 'pressure', signal()), /retainTokens .* must be less than threshold/);
});

test('small windows cannot bypass headroom and output capacity errors', async () => {
  for (const contextWindow of [2000, 3000]) {
    const f = fixture({
      config: { thresholdTokens: 400000, headroomTokens: 1000 },
      callConfig: { ...route, maxTokens: 2000 },
      contextWindow,
    });
    await assert.rejects(f.engine.compactIfNeeded(f.agent, 'pressure', signal()), /leaving no (message|pressure) budget/);
    assert.equal(f.calls.length, 0);
  }
});

test('an unrouted session never guesses a pressure budget', async () => {
  const f = fixture({ config: { thresholdTokens: 400000 }, callConfig: null });
  f.history();
  assert.equal(await f.engine.compactIfNeeded(f.agent, 'pressure', signal()), null);
  assert.equal(f.resolutions.length, 0);
});

test('absolute threshold schema accepts global and per-route positive safe integers', () => {
  const configured = BasicCompactionEngine.Config({ thresholdTokens: 400000, modelPolicies: [{ ...route, thresholdTokens: 500000 }] });
  assert.equal(configured.thresholdTokens, 400000);
  assert.equal(configured.modelPolicies[0].thresholdTokens, 500000);
  assert.equal(fixture({ config: configured }).engine.config.thresholdTokens, 400000);
});

test('completed summary usage is durable, ignorable and correlated before checkpoint commit', async () => {
  const usage = { inputTokens: 10, cacheReadTokens: 3000, outputTokens: 25 };
  const f = fixture({
    async *stream() {
      yield { type: 'text-delta', index: 0, text: 'A useful checkpoint.' };
      yield { type: 'usage', usage };
      yield { type: 'finish', reason: { kind: 'stop' } };
    },
  });
  const { first, result } = f.history();
  await f.engine.compactRegion(first.seq, result.seq, f.agent, signal());
  const events = f.session.snapshotEvents();
  const record = events.find((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  const summary = events.find((event) => event.type === 'compaction/summary');
  assert.ok(record);
  assert.equal(record.ignorable, true);
  assert.equal(record.data.compactionId, summary.data.compactionId);
  assert.deepEqual(record.data.usage, usage);
  assert.equal(record.data.outcome, 'completed');
  assert.equal(record.data.provider, route.provider);
  assert.equal(record.data.model, route.model);
  assert.ok(record.seq < summary.seq);
  assert.equal(f.session.surface.nodes.includes(record.seq), false);
  const restored = Session.create(f.session.id, events);
  assert.deepEqual(restored.deriveMessages(), f.session.deriveMessages());
  assert.deepEqual(restored.eventAt(record.seq), record);
});

test('summary rejected as non-shrinking still records reported usage', async () => {
  const usage = { inputTokens: 30, outputTokens: 5000 };
  const f = fixture({
    async *stream() {
      yield { type: 'text-delta', index: 0, text: 'S'.repeat(20000) };
      yield { type: 'usage', usage };
      yield { type: 'finish', reason: { kind: 'stop' } };
    },
  });
  const { first, result } = f.history();
  const before = f.session.deriveMessages();
  await assert.rejects(f.engine.compactRegion(first.seq, result.seq, f.agent, signal()), /summary is not smaller/);
  const events = f.session.snapshotEvents();
  assert.equal(events.some((event) => event.type === 'compaction/summary'), false);
  const record = events.find((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  assert.deepEqual(record?.data.usage, usage);
  assert.equal(record.data.outcome, 'completed');
  assert.deepEqual(f.session.deriveMessages(), before);
});

test('stream errors retain partial usage without changing history or hiding the error', async () => {
  const usage = { inputTokens: 25, outputTokens: 3 };
  const failure = new Error('stream interrupted');
  const f = fixture({
    async *stream() {
      yield { type: 'usage', usage };
      throw failure;
    },
  });
  const { first, result } = f.history();
  const before = f.session.deriveMessages();
  await assert.rejects(f.engine.compactRegion(first.seq, result.seq, f.agent, signal()), (error) => error === failure);
  const record = f.session.snapshotEvents().find((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  assert.deepEqual(record?.data.usage, usage);
  assert.equal(record.data.outcome, 'error');
  assert.deepEqual(f.session.deriveMessages(), before);
});

test('summary recovery records each attempt under one compaction identity', async () => {
  const usage = { inputTokens: 50, outputTokens: 5 };
  const f = fixture({
    async *stream(options, attempt) {
      yield { type: 'usage', usage };
      if (attempt === 1) throw new LlmError('recoverable summary error', 'IMAGE_OFFLOAD_REQUIRED');
      yield { type: 'text-delta', index: 0, text: 'Recovered checkpoint.' };
      yield { type: 'finish', reason: { kind: 'stop' } };
    },
  });
  f.ctx.on('compaction/summary-error', ({ error }, next) => error.code === 'IMAGE_OFFLOAD_REQUIRED' ? true : next());
  const { first, result } = f.history();
  await f.engine.compactRegion(first.seq, result.seq, f.agent, signal());
  const records = f.session.snapshotEvents().filter((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  assert.equal(records.length, 2);
  assert.equal(records[0].data.compactionId, records[1].data.compactionId);
  assert.deepEqual(records.map((record) => record.data.outcome), ['error', 'completed']);
  assert.deepEqual(records.map((record) => record.data.usage), [usage, usage]);
});

test('terminal summary truncation remains fail-closed with reported usage', async () => {
  const f = fixture({
    async *stream() {
      yield { type: 'text-delta', index: 0, text: 'Incomplete checkpoint.' };
      yield { type: 'usage', usage: { inputTokens: 10, outputTokens: 2048 } };
      yield { type: 'finish', reason: { kind: 'max-tokens' } };
    },
  });
  const { first, result } = f.history();
  const before = f.session.deriveMessages();
  await assert.rejects(f.engine.compactRegion(first.seq, result.seq, f.agent, signal()), /truncated at the token cap/);
  assert.deepEqual(f.session.deriveMessages(), before);
  const record = f.session.snapshotEvents().find((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  assert.equal(record.data.outcome, 'error');
  assert.equal(record.data.usage.outputTokens, 2048);
});

test('usage-less failed calls are recorded as unknown, not zero estimates', async () => {
  const f = fixture({
    async *stream() {
      throw new LlmError('cancelled', 'ABORTED');
    },
  });
  const { first, result } = f.history();
  await assert.rejects(f.engine.compactRegion(first.seq, result.seq, f.agent, signal()), /cancelled/);
  const record = f.session.snapshotEvents().find((event) => event.type === 'plugin:cache-efficiency/compaction-usage');
  assert.ok(record);
  assert.equal(Object.hasOwn(record.data, 'usage'), false);
  assert.equal(record.data.outcome, 'error');
});

for (const value of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, Infinity, NaN, '400000', null]) {
  test(`absolute threshold rejects invalid ${String(value)}`, () => {
    assert.throws(() => fixture({ config: { thresholdTokens: value } }), /thresholdTokens.*positive safe integer/);
    assert.throws(() => fixture({ config: { modelPolicies: [{ ...route, thresholdTokens: value }] } }), /thresholdTokens.*positive safe integer/);
    assert.throws(() => fixture({ config: BasicCompactionEngine.Config({ thresholdTokens: value }) }));
    assert.throws(() => fixture({ config: BasicCompactionEngine.Config({ modelPolicies: [{ ...route, thresholdTokens: value }] }) }));
  });
}
