import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';

const root = process.env.DSH_KERNEL_ROOT;
if (!root) throw new Error('DSH_KERNEL_ROOT must name the patched kernel node_modules/@deepseek-ai directory');
const require = createRequire(path.join(root, 'dsh-token-meter/package.json'));
const { z } = require('zod');
const { Context } = await import(pathToFileURL(path.join(root, 'cordis/lib/index.js')));
const { SessionProjectionRegistry } = await import(pathToFileURL(path.join(root, 'dsh-session-projection/lib/index.js')));
const { TokenMeter } = await import(pathToFileURL(path.join(root, 'dsh-token-meter/lib/index.js')));
const { scopedUsageProjectionDefinition: definition } = await import(pathToFileURL(path.join(root, 'dsh-token-meter/lib/cache-usage/projection.mjs')));
const header = { id: 'child' };
const usage = { inputTokens: 20, cacheReadTokens: 80, cacheWriteTokens: 0, outputTokens: 10, totalTokens: 110 };
const events = [
  { seq: 0, type: 'assistant/message', data: { turn: 1, step: 1, usage, stream: [] } },
  { seq: 1, type: 'session/end-seed', data: { inherited: true } },
  { seq: 2, type: 'assistant/message', data: { turn: 2, step: 1, usage, stream: [] } },
  { seq: 3, type: 'compaction/start', data: { compactionId: 'c' } },
  { seq: 4, type: 'plugin:cache-efficiency/compaction-usage', ignorable: true, data: {
    compactionId: 'c', provider: 'p', model: 'm', usage, outcome: 'completed',
  } },
  { seq: 5, type: 'compaction/summary', data: { compactionId: 'c', usage } },
  { seq: 6, type: 'compaction/end', data: { compactionId: 'c' } },
];

function registryFor() {
  const ctx = new Context();
  const registry = new SessionProjectionRegistry(ctx);
  registry.register(definition);
  return { ctx, registry };
}

const value = definition.wire.view(events.reduce(definition.apply, definition.init(header, 2)));

test('patched token-meter registers scoped projection without altering legacy registration', async () => {
  const ctx = new Context();
  const registry = new SessionProjectionRegistry(ctx);
  new TokenMeter(ctx);
  const restored = registry.viewCheckpoint({});
  assert.deepEqual(restored, {});
  assert.ok(registry.registrations.has('tokenUsage'));
  assert.ok(registry.registrations.has('scopedUsage'));
  await ctx.fiber.dispose();
});

test('actual registry restores full cold logs and validated checkpoint tails without double counting', async () => {
  const { ctx, registry } = registryFor();
  const first = registry.restore({}, events.slice(0, 5), 0, header, 2);
  const checkpoint = JSON.parse(JSON.stringify(first.checkpoint));
  assert.equal(first.snapshot.values.scopedUsage.ordinary.calls, 1);
  assert.equal(first.snapshot.values.scopedUsage.summaries.calls, 1);
  assert.equal(registry.restoreFloor(checkpoint), 4);
  const fromTail = registry.restore(checkpoint, events.slice(4), 4, header, 2);
  const full = registry.restore({}, events, 0, header, 2);
  assert.deepEqual(fromTail.snapshot.values.scopedUsage, full.snapshot.values.scopedUsage);
  assert.equal(full.snapshot.values.scopedUsage.summaries.totalTokens, 110);
  assert.equal(full.snapshot.values.scopedUsage.legacySummaries, 0);
  assert.deepEqual(registry.viewCheckpoint(fromTail.checkpoint).scopedUsage, value);
  const old = { scopedUsage: { ver: 1, seq: 6, val: { obsolete: true } } };
  assert.equal(registry.restoreFloor(old), 0);
  assert.deepEqual(registry.viewCheckpoint(old), {});
  assert.deepEqual(registry.restore(old, events, 0, header, 2).snapshot.values.scopedUsage, value);
  assert.throws(() => registry.restore(checkpoint, events.slice(2, 4), 2, header, 2), /re-read from seq 0/);
  await ctx.fiber.dispose();
});

test('version-two cold replay preserves inherited provider provenance but excludes inherited spend', async () => {
  const { ctx, registry } = registryFor();
  const historicalUsage = { inputTokens: 20, cacheReadTokens: 80, outputTokens: 10 };
  const own = [
    { seq: 0, type: 'request/header', data: { header: { config: { provider: 'codex' } } } },
    { seq: 1, type: 'assistant/message', data: { turn: 1, step: 1, usage: historicalUsage } },
    { seq: 2, type: 'session/end-seed', data: { inherited: true } },
    { seq: 3, type: 'assistant/attempt', data: { turn: 1, step: 1, stream: [{ type: 'chunk', chunk: { type: 'usage', usage: historicalUsage } }] } },
  ];
  const inherited = registry.restore({}, own.slice(0, 3), 0, header, 3);
  assert.equal(inherited.checkpoint.scopedUsage.ver, 2);
  assert.equal(inherited.checkpoint.scopedUsage.val.provider, 'codex');
  assert.equal(inherited.snapshot.values.scopedUsage.ordinary.calls, 0);
  const restored = registry.restore(JSON.parse(JSON.stringify(inherited.checkpoint)), own.slice(2), 2, header, 3);
  assert.equal(restored.snapshot.values.scopedUsage.ordinary.measuredCalls, 1);
  assert.equal(restored.snapshot.values.scopedUsage.ordinary.totalTokens, 110);
  assert.equal(restored.snapshot.values.scopedUsage.ordinary.cacheEligibleReadTokens, 80);
  const deployedOld = { scopedUsage: { ver: 1, seq: 3, val: { obsolete: true } } };
  assert.equal(registry.restoreFloor(deployedOld), 0);
  assert.deepEqual(registry.restore(deployedOld, own, 0, header, 3).snapshot.values, restored.snapshot.values);
  await ctx.fiber.dispose();
});

const subscriptionsRoot = process.env.DSH_SUBSCRIPTIONS_ROOT;

test('real Responses adapter usage shape is measured with durable Codex provenance', { skip: !subscriptionsRoot }, async () => {
  const { mapResponsesUsage } = await import(pathToFileURL(path.join(subscriptionsRoot, 'lib/translate/responses.js')));
  const adapted = mapResponsesUsage({ input_tokens: 100, output_tokens: 10, input_tokens_details: { cached_tokens: 80 }, output_tokens_details: { reasoning_tokens: 5 } });
  const recorded = definition.apply(definition.init(header, 0), {
    seq: 0, type: 'assistant/message', data: { turn: 1, step: 1, message: { source: { provider: 'codex', model: 'gpt-6-astra' } }, usage: adapted },
  });
  assert.equal(recorded.ordinary.measuredCalls, 1);
  assert.equal(recorded.ordinary.totalTokens, 110);
  assert.equal(recorded.ordinary.cacheMeasuredCalls, 1);
  assert.equal(recorded.ordinary.cacheEligibleInputTokens, 100);
  assert.equal(recorded.ordinary.cacheEligibleReadTokens, 80);
  const omittedRead = mapResponsesUsage({ input_tokens: 100, output_tokens: 10 });
  const missing = definition.apply(definition.init(header, 0), {
    seq: 0, type: 'assistant/message', data: { turn: 1, step: 1, message: { source: { provider: 'codex', model: 'gpt-6-astra' } }, usage: omittedRead },
  });
  assert.equal(missing.ordinary.cacheMeasuredCalls, 0);
  assert.equal(missing.ordinary.missingCacheRead, 1);
});

test('state validation survives unknown usage, malformed plugin data and aggregate overflow', () => {
  const state = events.reduce(definition.apply, definition.init(header, 2));
  const unknown = definition.apply(state, { seq: 7, type: 'assistant/attempt', data: { turn: 2, step: 2, stream: [] } });
  assert.doesNotThrow(() => definition.stateSchema.parse(JSON.parse(JSON.stringify(unknown))));
  const malformed = definition.apply(unknown, { seq: 8, type: 'plugin:cache-efficiency/compaction-usage', ignorable: true, data: [] });
  assert.equal(malformed, unknown);
  const large = definition.apply(unknown, { seq: 8, type: 'assistant/message', data: {
    turn: 2, step: 3, stream: [], usage: { inputTokens: Number.MAX_SAFE_INTEGER, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
  } });
  assert.equal(large.ordinary.totalTokens, null);
  assert.doesNotThrow(() => definition.stateSchema.parse(large));
});

test('real host and remote descriptors preserve optional scoped usage on projection responses', async () => {
  for (const file of ['typert.host.js', 'typert.remote-client.js']) {
    const mod = await import(pathToFileURL(path.join(root, 'dsh-api-session-controller/lib', file)));
    const contract = mod.TYPERT ?? mod.TYPERT_REMOTE;
    const descriptors = contract.invocations ?? contract.descriptors;
    const descriptor = descriptors.find(item => item.id.endsWith('#session/projections'));
    const schema = descriptor.result.create();
    const response = { kind: 'sequenced', asOfSeq: 6, values: { scopedUsage: value } };
    assert.deepEqual(schema.parse(response).values.scopedUsage, value);
    assert.deepEqual(schema.parse({ kind: 'sequenced', asOfSeq: 0, values: {} }).values, {});
    assert.equal(schema.safeParse({ ...response, values: { scopedUsage: { ...value, ordinary: { ...value.ordinary, calls: -1 } } } }).success, false);
  }
});

const webRoot = process.env.DSH_WEB_ROOT;

test('actual browser codec retains scoped usage for all five response schemas', { skip: !webRoot }, () => {
  const source = readFileSync(path.join(webRoot, 'dsh-api-remotes/lib/client.js'), 'utf8');
  const start = source.indexOf('function createScopedUsageSchemas');
  const end = source.indexOf('let JsonValueRemoteCodec$schema$value;', start);
  assert.ok(start > 0 && end > start);
  const context = { number: z.number, object: z.object, string: z.string, literal: z.literal, boolean: z.boolean };
  vm.runInNewContext(source.slice(start, end) + '\nglobalThis.schema = scopedUsageSchema;', context);
  assert.deepEqual(context.schema.parse(value), value);
  assert.equal(source.match(/"scopedUsage": scopedUsageSchema.optional\(\)/g)?.length, 5);
  assert.doesNotThrow(() => new vm.Script(source));
  const client = readFileSync(path.join(webRoot, 'dsh-client-ui-chat/lib/client.js'), 'utf8');
  assert.match(client, /data-scoped-usage/);
  assert.match(client, /scopedUsageSessions: ctx.sessions.list/);
  assert.doesNotThrow(() => new vm.Script(client));
});
