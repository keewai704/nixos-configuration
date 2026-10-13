import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const kernelRoot = resolve(process.env.DSH_TEST_KERNEL ?? process.cwd());
const require = createRequire(join(kernelRoot, 'package.json'));
const { Context, Service } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis')).href);
const { default: LlmRuntime, LlmAdapter } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-llm')).href);
const source = resolve(process.env.DSH_BUDGET_TEST_SOURCE ?? dirname(fileURLToPath(import.meta.url)));

async function fixture(t, config = {}) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'dsh-budget-cordis-'));
  const moduleRoot = join(root, 'module');
  mkdirSync(moduleRoot);
  for (const name of ['budget.mjs', 'budget-policy.mjs', 'budget-plugin.mjs']) copyFileSync(join(source, name), join(moduleRoot, name));
  symlinkSync(join(kernelRoot, 'node_modules'), join(moduleRoot, 'node_modules'));
  const previousHome = process.env.DSH_HOME;
  process.env.DSH_HOME = root;
  const ctx = new Context();
  const agents = new Map();
  const headers = new Map();
  const flushed = [];
  let admit;
  let flush = async session => { flushed.push(session); return true; };
  let providerCalls = 0;
  const frames = [
    { type: 'usage', usage: { inputTokens: 3, outputTokens: 7, cacheReadTokens: 0, cacheWriteTokens: 0 } },
    { type: 'finish', reason: { kind: 'stop' } },
  ];
  class Adapter extends LlmAdapter {
    async *stream() { providerCalls++; for (const frame of frames) yield frame; }
  }
  t.after(async () => {
    try { await ctx.fiber.dispose(); }
    finally {
      if (previousHome === undefined) delete process.env.DSH_HOME;
      else process.env.DSH_HOME = previousHome;
      assert.equal(realpathSync(root), root);
      assert.match(root, /\/dsh-budget-cordis-[^/]+$/);
      rmSync(root, { recursive: true });
    }
  });
  await ctx.plugin(LlmRuntime);
  await ctx.plugin({ apply(child) {
    child.provide('sessions', { flush: session => flush(session) });
    child.provide('sessionPersistence', { stat: async id => headers.has(id) ? { header: headers.get(id) } : undefined });
  } });
  class Subagents extends Service {
    constructor(child) { super(child, 'subagents'); }
    registerAdmission(callback) {
      return this.ctx.effect(() => {
        assert.equal(admit, undefined);
        admit = callback;
        return () => { admit = undefined; };
      });
    }
  }
  await ctx.plugin(Subagents);
  ctx.get('llm').registerAdapter(['fixture'], new Adapter());
  const plugin = await import(pathToFileURL(join(moduleRoot, 'budget-plugin.mjs')).href);
  assert.equal(plugin.inject.includes('agents'), false);
  const budgetFiber = await ctx.plugin(plugin, config);
  assert.equal(budgetFiber.state, 2);
  assert.equal(ctx.get('agents'), undefined);
  let initiator;
  class Agents extends Service {
    constructor(child) { super(child, 'agents'); }
    get(id) { return agents.get(id); }
    currentInitiator() { return initiator; }
  }
  const agentsFiber = await ctx.plugin(Agents);
  function agent(id, parentId) {
    const header = { id, createdAt: id === 'root' ? 1 : 2, ...(parentId === undefined ? {} : { parentSession: parentId }) };
    const controller = new AbortController();
    const value = { id, session: { header }, options: { provider: 'fixture', model: 'm' }, cancel() { controller.abort(); } };
    agents.set(id, value); headers.set(id, header);
    return { value, controller };
  }
  const rootAgent = agent('root');
  initiator = rootAgent.value;
  return {
    ctx, agent, rootAgent, budgetFiber, agentsFiber, flushed,
    policy: ctx.get('budgetPolicy'),
    get providerCalls() { return providerCalls; },
    get admission() { return admit; },
    setFlush(callback) { flush = callback; },
    async stream(id = 'root') {
      const chunks = [];
      for await (const chunk of ctx.get('llm').stream({ provider: 'fixture', model: 'm', sessionId: id, messages: [], signal: rootAgent.controller.signal })) chunks.push(chunk);
      return chunks;
    },
  };
}

test('actual Cordis budget plugin starts before agents and gates the real LLM middleware', async t => {
  const f = await fixture(t, { limits: { maxRequests: 1 } });
  const chunks = await f.stream();
  assert.equal(chunks.at(-1).reason.kind, 'stop');
  assert.equal(f.providerCalls, 1);
  assert.equal(f.flushed.length, 1);
  assert.equal(f.policy.snapshot('root').requests, 1);
  assert.equal(f.policy.snapshot('root').usage.outputTokens, 7);
  await assert.rejects(f.stream(), /request budget/);
  assert.equal(f.providerCalls, 1);
});

test('actual Cordis late child lineage resolves the parent without undeclared injection', async t => {
  const f = await fixture(t);
  const child = f.agent('child', 'root');
  await f.policy.bindSession(child.value.session.header);
  assert.equal(f.policy.snapshot('child').rootSessionId, 'root');
  await f.stream('child');
  assert.equal(f.policy.snapshot('root').requests, 1);
});

for (const mode of ['false', 'reject']) test(`actual Cordis flush ${mode} never reaches the fake adapter or charges usage`, async t => {
  const f = await fixture(t, { limits: { maxRequests: 1 } });
  f.setFlush(async () => { if (mode === 'reject') throw new Error('flush fixture failure'); return false; });
  await assert.rejects(f.stream(), /checkpoint|flush fixture failure/);
  assert.equal(f.providerCalls, 0);
  const state = f.policy.snapshot('root');
  assert.equal(state.requests, 0);
  assert.equal(state.ambiguousRequests, 0);
  assert.equal(state.requestRecords[0].state, 'cancelled');
});

test('actual Cordis missing registry fails closed after provider removal', async t => {
  const f = await fixture(t);
  await f.agentsFiber.dispose();
  assert.equal(f.ctx.get('agents'), undefined);
  await assert.rejects(f.stream(), /agent|registry|unavailable/i);
  assert.equal(f.providerCalls, 0);
});

test('actual Cordis budget disposal closes its durable policy and unregisters middleware', async t => {
  const f = await fixture(t);
  await f.stream();
  await f.budgetFiber.dispose();
  assert.equal(f.ctx.get('budgetPolicy'), undefined);
  assert.equal(f.admission, undefined);
  assert.throws(() => f.policy.snapshot('root'), /closed/);
});
