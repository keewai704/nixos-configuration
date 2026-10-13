import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { BudgetLedger } from './budget.mjs';
import { createBudgetPolicy } from './budget-policy.mjs';

function fixture(t, config = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'dsh-budget-policy-'));
  const controller = new AbortController();
  const parent = { id: 'root', session: { header: { id: 'root', createdAt: 1 } }, cancel() { controller.abort(); } };
  const ledger = new BudgetLedger(join(dir, 'budget.sqlite'));
  const ctx = { agents: { get: id => id === 'root' ? parent : undefined, currentInitiator: () => parent }, sessions: { flush: async () => true }, sessionPersistence: { stat: async () => undefined } };
  ctx.get = name => ctx[name];
  const policy = createBudgetPolicy(ctx, ledger, config);
  t.after(async () => { await policy.close(); assert.ok(dir.startsWith(join(tmpdir(), 'dsh-budget-policy-'))); rmSync(dir, { recursive: true }); });
  return { ledger, policy, parent, controller, ctx };
}

async function collect(stream) { const chunks = []; for await (const item of stream) chunks.push(item); return chunks; }
const options = { provider: 'deepseek-official', model: 'm', maxTokens: 20, sessionId: 'root' };
const usage = { inputTokens: 5, outputTokens: 7, cacheReadTokens: 0, cacheWriteTokens: 0 };
const result = async function* () { yield { type: 'usage', usage }; yield { type: 'finish', reason: { kind: 'stop' } }; };

test('plugin reserves before next and settles durably before finish reaches caller', async t => {
  const { ledger, policy } = fixture(t, { limits: { maxRequests: 1, maxOutputTokens: 100 } });
  let called = 0;
  const stream = policy.stream(options, async function* () {
    called++;
    assert.equal(ledger.snapshot('root').reserved.outputTokens, 20);
    yield* result();
  });
  for await (const chunk of stream) if (chunk.type === 'finish') assert.equal(ledger.snapshot('root').usage.outputTokens, 7);
  await assert.rejects(collect(policy.stream(options, () => { called++; return result(); })), /request budget/);
  assert.equal(called, 1);
});

for (const failure of ['false', 'reject']) test(`session checkpoint ${failure} cancels the undispatched reservation without ambiguous billing`, async t => {
  const { ledger, policy, ctx, parent } = fixture(t, { limits: { maxRequests: 1, maxOutputTokens: 100 } });
  let providerCalls = 0;
  ctx.sessions.flush = async session => {
    assert.equal(session, parent.session);
    assert.equal(ledger.snapshot('root').requestRecords[0].state, 'reserved');
    if (failure === 'reject') throw new Error('checkpoint unavailable');
    return false;
  };
  await assert.rejects(collect(policy.stream(options, () => { providerCalls++; return result(); })), /checkpoint/i);
  const state = ledger.snapshot('root');
  assert.equal(providerCalls, 0);
  assert.equal(state.requests, 0);
  assert.equal(state.ambiguousRequests, 0);
  assert.equal(state.reserved.outputTokens, 0);
  assert.equal(state.requestRecords[0].state, 'cancelled');
  ctx.sessions.flush = async () => true;
  await collect(policy.stream(options, () => { providerCalls++; return result(); }));
  assert.equal(providerCalls, 1);
  assert.equal(ledger.snapshot('root').requests, 1);
});

test('session checkpoint must acknowledge durability before request dispatch', async t => {
  const { ledger, policy, ctx } = fixture(t, { limits: { maxRequests: 1 } });
  const entered = Promise.withResolvers();
  const checkpoint = Promise.withResolvers();
  let providerCalls = 0;
  ctx.sessions.flush = () => { entered.resolve(); return checkpoint.promise; };
  const running = collect(policy.stream(options, () => { providerCalls++; return result(); }));
  await entered.promise;
  assert.equal(providerCalls, 0);
  assert.equal(ledger.snapshot('root').requestRecords[0].state, 'reserved');
  checkpoint.resolve(true);
  await running;
  assert.equal(providerCalls, 1);
});

test('retry attempts consume independent request reservations', async t => {
  const { ledger, policy } = fixture(t, { limits: { maxRequests: 2 } });
  const failed = async function* () { yield { type: 'finish', reason: { kind: 'error' } }; };
  await collect(policy.stream(options, failed));
  await collect(policy.stream(options, result));
  assert.equal(ledger.snapshot('root').requests, 2);
  assert.equal(ledger.snapshot('root').ambiguousRequests, 1);
});

test('a thrown request retains unknown billing and blocks configured hard limit', async t => {
  const { ledger, policy } = fixture(t, { limits: { maxOutputTokens: 100 } });
  await assert.rejects(collect(policy.stream(options, async function* () { throw new Error('transport'); })), /transport/);
  assert.equal(ledger.snapshot('root').ambiguousRequests, 1);
  await assert.rejects(collect(policy.stream(options, result)), /ambiguous usage/);
});

test('request middleware clamps audited provider output but refuses unknown routes', async t => {
  const { policy, parent, controller } = fixture(t, { limits: { maxOutputTokens: 100 }, routes: { 'deepseek-official/m': { maxOutputTokens: 30 } } });
  assert.equal((await policy.request({ agent: parent, signal: controller.signal }, async () => ({ provider: 'deepseek-official', model: 'm', maxTokens: 100 }))).maxTokens, 30);
  await assert.rejects(policy.request({ agent: parent, signal: controller.signal }, async () => ({ provider: 'codex', model: 'm' })), /audited route/);
});

test('operator-attested priced bound admits cost while unknown prices fail closed', async t => {
  const pricing = { input: 1_000_000, output: 2_000_000, cacheRead: 0, cacheWrite: 1_000_000 };
  const { ledger, policy } = fixture(t, { limits: { maxCostMicros: 300 }, routes: { 'deepseek-official/m': { maxOutputTokens: 20, inputTokenUpperBound: 40, pricing } } });
  await collect(policy.stream(options, result));
  assert.equal(ledger.snapshot('root').usage.costMicros, 19);
  await assert.rejects(collect(policy.stream({ ...options, model: 'unknown' }, result)), /known billing/);
});

test('deadline cancels a live request and marks unknown usage ambiguous', async t => {
  const { policy, controller, ledger } = fixture(t, { limits: { deadlineAt: Date.now() + 50 } });
  await collect(policy.stream({ ...options, signal: controller.signal }, async function* () {
    await new Promise(resolve => { if (controller.signal.aborted) resolve(); else controller.signal.addEventListener('abort', resolve, { once: true }); });
    yield { type: 'finish', reason: { kind: 'aborted' } };
  }));
  assert.equal(controller.signal.aborted, true);
  assert.equal(ledger.snapshot('root').ambiguousRequests, 1);
});

test('child deadline signal and uncertain disposal preserve its slot', async t => {
  const { policy, parent, controller, ledger } = fixture(t, { limits: { deadlineAt: Date.now() + 50, maxConcurrentChildren: 1 } });
  const lease = await policy.admitChild({ parent, childId: 'external', kind: 'external', provider: 'opaque', signal: controller.signal });
  await new Promise(resolve => { if (lease.signal.aborted) resolve(); else lease.signal.addEventListener('abort', resolve, { once: true }); });
  lease.settle({ quiescent: false });
  assert.equal(ledger.snapshot('root').ambiguousChildren, 1);
});

test('policy disposal cancels and drains a live request before closing SQLite', async t => {
  const { policy, controller } = fixture(t);
  const entered = Promise.withResolvers();
  const running = collect(policy.stream({ ...options, signal: controller.signal }, async function* () {
    entered.resolve();
    await new Promise(resolve => controller.signal.addEventListener('abort', resolve, { once: true }));
    yield { type: 'finish', reason: { kind: 'aborted' } };
  }));
  await entered.promise;
  await policy.close();
  await running;
  assert.equal(controller.signal.aborted, true);
});

for (const kind of ['error', 'aborted']) test(`partial usage followed by ${kind} never refunds the reserved maximum`, async t => {
  const { policy, ledger } = fixture(t, { limits: { maxOutputTokens: 100 } });
  await collect(policy.stream(options, async function* () { yield { type: 'usage', usage }; yield { type: 'finish', reason: { kind } }; }));
  assert.equal(ledger.snapshot('root').usage.outputTokens, 0);
  assert.equal(ledger.snapshot('root').reserved.outputTokens, 20);
  assert.equal(ledger.snapshot('root').ambiguousRequests, 1);
});

test('root deadline cancels a parked tool after the model stream ended and awaits cleanup', async t => {
  const { policy, parent, controller } = fixture(t, { limits: { deadlineAt: Date.now() + 70 } });
  await collect(policy.stream({ ...options, signal: controller.signal }, result));
  const exec = { agent: parent, signal: controller.signal };
  const cleanup = Promise.withResolvers();
  const cancelled = Promise.withResolvers();
  let finished = false;
  const call = policy.tool(exec, async () => {
    await new Promise(resolve => { if (exec.signal.aborted) resolve(); else exec.signal.addEventListener('abort', resolve, { once: true }); });
    cancelled.resolve();
    await cleanup.promise;
    return { value: 'stopped' };
  }).then(value => { finished = true; return value; });
  await cancelled.promise;
  assert.equal(controller.signal.aborted, true);
  assert.equal(finished, false);
  cleanup.resolve();
  assert.deepEqual(await call, { value: 'stopped' });
  assert.equal(exec.signal, controller.signal);
  await assert.rejects(policy.tool(exec, async () => assert.fail('expired tool dispatched')), /deadline/);
});

test('lineage cycles are rejected rather than hanging', async t => {
  const { policy, ctx } = fixture(t);
  ctx.sessionPersistence.stat = async id => ({ header: { id, createdAt: 1, parentSession: id === 'a' ? 'b' : 'a' } });
  await assert.rejects(policy.bindSession({ id: 'a', createdAt: 1, parentSession: 'b' }), /cycle/);
});
