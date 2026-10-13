import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const kernel = resolve(process.env.DSH_TEST_KERNEL ?? process.cwd());
const source = resolve(process.env.DSH_TEST_SOURCE ?? process.env.DSH_LOCALE_UPSTREAM ?? process.cwd());
const composition = resolve(process.env.DSH_COMPOSITION_SOURCE ?? dirname(fileURLToPath(import.meta.url)));
const require = createRequire(join(kernel, 'package.json'));
const loadModule = name => import(pathToFileURL(require.resolve(name)).href);
const { Context, Service } = await loadModule('@deepseek-ai/cordis');
const { default: Loader } = await loadModule('@deepseek-ai/cordis-plugin-loader');
const { default: Include, entryListSchema, applyEntryPatches } = await loadModule('@deepseek-ai/cordis-plugin-include');
const { LlmAdapter, createUserMessage } = await loadModule('@deepseek-ai/dsh-llm');
const { default: AgentLoop } = await loadModule('@deepseek-ai/dsh-agent-loop');
const { buildComposition } = await import(pathToFileURL(join(composition, 'build-composition.mjs')).href);
const dispatchGuard = await import(pathToFileURL(join(composition, 'budget-guard.mjs')).href);
const yaml = require('js-yaml');
const parse = text => yaml.load(text, { schema: entryListSchema });
const load = file => parse(readFileSync(file, 'utf8'));
const patch = (rows, changes) => applyEntryPatches(rows, changes, (message, ...args) => assert.fail(`${message}: ${args.join(', ')}`));
const flatten = rows => rows.flatMap(row => [row, ...(row.group && Array.isArray(row.config) ? flatten(row.config) : [])]);
const external = JSON.parse(process.env.DSH_TEST_ADAPTER_PATCHES ?? '[]');
const layers = ['packages/bundle/base/cordis.patch.yml', 'packages/bundle/web-app/cordis.patch.yml', ...['standard', 'ptc', 'minimal', 'cordis'].map(name => `packages/bundle/web-app/presets/${name}.patch.yml`)];
const original = [...layers.map(file => join(source, file)), ...external].reduce((rows, file) => patch(rows, load(file)), []);
const generated = parse(await buildComposition(source, kernel));
const missingExternal = new Set(external.length ? [] : ['llm-subscriptions', 'llm-claude-code']);
const configured = patch(original, generated.filter(row => !missingExternal.has(row.id)));
const adapters = flatten(original).filter(row => /^llm-/.test(row.id) && row.id !== 'llm-retry');
const loopRow = flatten(configured).find(row => row.name === '@deepseek-ai/dsh-agent-loop');
const guardRow = flatten(configured).find(row => row.name === '@keewai/dsh-operations/budget-guard');
const policyRow = flatten(configured).find(row => row.name === '@keewai/dsh-operations/budget');
const guarded = [loopRow, ...adapters.map(row => flatten(configured).find(entry => entry.id === row.id))];
const options = provider => ({ provider, model: 'fixture', messages: [], signal: new AbortController().signal });
const collect = async stream => { const chunks = []; for await (const chunk of stream) chunks.push(chunk); return chunks; };
const send = agent => agent.followup(createUserMessage({ content: [{ type: 'text', text: 'fixture' }], source: { kind: 'user' } }));

async function include(t, rows, modules, profile = 'web') {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'dsh-composition-'));
  const ctx = new Context();
  let tree;
  t.after(async () => {
    try { await ctx.fiber.dispose(); }
    finally {
      assert.equal(realpathSync(root), root);
      assert.match(root, /\/dsh-composition-[^/]+$/);
      rmSync(root, { recursive: true });
    }
  });
  ctx.provide('profileContext', { name: profile });
  await ctx.plugin(Loader);
  Object.assign(ctx.get('loader').builtins, modules, { include: Include });
  const path = join(root, 'entries.yml');
  writeFileSync(path, yaml.dump(rows.map(row => ({ ...row, name: `cordis:${row.name}` })), { schema: entryListSchema }));
  await ctx.get('loader').root.update([{ id: 'fixture-config', name: 'cordis:include', config: { path: pathToFileURL(path).href } }]);
  await ctx.get('loader').await();
  tree = ctx.get('loader').resolve('fixture-config').subtree;
  assert.ok(tree instanceof Include);
  await tree.await();
  return { ctx, tree };
}

async function fixture(t, deferredDependencies = false) {
  const state = { calls: 0, cleaned: 0, hold: false, started: Promise.withResolvers() };
  const modules = { [loopRow.name]: AgentLoop, [guardRow.name]: dispatchGuard };
  for (const row of adapters) modules[row.name] = class {
    static inject = ['llm', 'fixtureReady'];
    constructor(ctx) {
      ctx.llm.registerAdapter([row.id], new class extends LlmAdapter {
        async *stream(request) {
          state.calls++;
          if (state.hold) {
            state.started.resolve(request.signal);
            try {
              await new Promise((_, reject) => {
                if (request.signal.aborted) return reject(request.signal.reason);
                request.signal.addEventListener('abort', () => reject(request.signal.reason), { once: true });
              });
            } finally { state.cleaned++; }
          }
          yield { type: 'block-start', index: 0, blockType: 'text' };
          yield { type: 'text-delta', index: 0, text: 'fixture' };
          yield { type: 'block-end', index: 0, block: { type: 'text', text: 'fixture' } };
          yield { type: 'finish', reason: { kind: 'stop' } };
        }
      }());
    }
  };
  modules[policyRow.name] = class extends Service {
    identity = Symbol('fixture-policy');
    constructor(ctx, config) { super(ctx, 'budgetPolicy'); this.config = config; }
    async [Service.init]() { if (this.config.fail) throw new Error('fixture policy startup failed'); }
  };
  const f = await include(t, [guardRow, ...guarded], modules);
  for (const name of ['dsh-llm', 'dsh-agent', 'dsh-session', 'dsh-session-projection', 'dsh-system-prompt']) {
    const { default: plugin } = await loadModule(`@deepseek-ai/${name}`);
    await f.ctx.plugin(plugin);
  }
  f.ready = async () => {
    const { default: Tools } = await loadModule('@deepseek-ai/dsh-tools');
    await f.ctx.plugin(Tools);
    await f.ctx.plugin({ apply(ctx) { ctx.provide('fixtureReady', {}); } });
    await f.tree.await();
  };
  if (!deferredDependencies) await f.ready();
  f.policy = async (fail = false) => {
    await f.tree.create({ ...policyRow, name: `cordis:${policyRow.name}`, config: { fail } });
    await f.tree.await();
    return f.tree.resolve(policyRow.id).fiber;
  };
  f.root = () => f.ctx.get('agents').create({ sessionId: 'fixture-root', agentOptions: { provider: adapters[0].id, model: 'fixture' } });
  return { ...f, state };
}

async function closed(f) {
  assert.equal(f.ctx.get('agentLoop'), undefined);
  assert.deepEqual(f.ctx.get('llm').listProviders(), []);
  await assert.rejects(f.root(), /factory|loop|unavailable/i);
  for (const row of adapters) {
    await assert.rejects(f.ctx.get('llm').prepareCall(options(row.id)), error => error.code === 'NO_ADAPTER');
    if (!f.ctx.get('budgetPolicy')) await assert.rejects(collect(f.ctx.get('llm').stream(options(row.id))), /Budget policy.*unavailable/);
    else assert.equal((await collect(f.ctx.get('llm').stream(options(row.id)))).at(-1).reason.failure.code, 'NO_ADAPTER', row.id);
  }
}

test('generated patches replace mounted implementations and transform every shipped delegation preset', async t => {
  if (!external.length) t.diagnostic('External adapter coverage requires DSH_TEST_ADAPTER_PATCHES; release checks must supply both bundle patches.');
  const intents = load(join(composition, 'cordis.patch.yml'));
  const replacements = intents.filter(row => row.name && flatten(original).some(before => before.id === row.id && before.name !== row.name));
  const selected = [];
  for (const intent of replacements) {
    const before = flatten(original).find(row => row.id === intent.id);
    const old = flatten(configured).find(row => row.id === intent.id);
    const replacement = flatten(configured).find(row => row.name === intent.name && row.id !== intent.id);
    assert.equal(old.disabled, true, intent.id);
    assert.ok(replacement, intent.name);
    assert.deepEqual(replacement.disabled, before.disabled, intent.id);
    assert.deepEqual(replacement.config, intent.config ?? before.config, intent.id);
    selected.push(old, replacement);
  }
  for (const profile of ['web', 'desktop']) {
    const active = new Set();
    const modules = Object.fromEntries(selected.map(row => [row.name, { apply(ctx) { active.add(row.id); ctx.effect(() => () => active.delete(row.id)); } }]));
    const f = await include(t, selected.map(row => ({ ...row, config: {} })), modules, profile);
    for (const row of selected) assert.equal(active.has(row.id), !f.tree.resolve(row.id).disabled, `${profile}/${row.id}`);
  }
  const presets = original.filter(row => Array.isArray(row.config?.plugins)).filter(row => flatten(row.config.plugins).some(child => child.name === '@deepseek-ai/dsh-workflow-ptc'));
  assert.ok(presets.length > 0);
  for (const preset of presets) {
    const effective = configured.find(row => row.id === preset.id);
    const children = flatten(effective.config.plugins);
    assert.equal(children.some(row => row.name === '@deepseek-ai/dsh-workflow-ptc'), false, preset.id);
    assert.equal(children.filter(row => row.name === '@keewai/dsh-operations/checkpoint-tools').length, 1, preset.id);
    assert.equal(children.filter(row => row.name === '@keewai/dsh-operations/message-policy').length, 1, preset.id);
    const workflows = children.filter(row => row.name === '@keewai/dsh-reliability/workflow');
    assert.equal(workflows.length, flatten(preset.config.plugins).filter(row => row.name === '@deepseek-ai/dsh-workflow-ptc').length, preset.id);
    for (const workflow of workflows) assert.deepEqual(workflow.inject.budgetPolicy, {});
  }
});

test('real Loader merges entry injection without replacing adapter or AgentLoop dependencies', async t => {
  const f = await fixture(t, true);
  const policy = await f.policy();
  assert.equal(policy.state, 2);
  await closed(f);
  assert.equal(f.state.calls, 0);
  for (const row of guarded) {
    const inject = f.tree.resolve(row.id).fiber.inject;
    assert.ok(Object.hasOwn(inject, 'budgetPolicy'), row.id);
    for (const key of row.id === loopRow.id ? AgentLoop.inject : ['llm', 'fixtureReady']) assert.ok(Object.hasOwn(inject, key), `${row.id}/${key}`);
  }
  await f.ready();
  assert.ok(f.ctx.get('agentLoop'));
  assert.deepEqual(f.ctx.get('llm').listProviders().map(row => row.id).sort(), adapters.map(row => row.id).sort());
  for (const row of adapters) assert.equal((await collect(f.ctx.get('llm').stream(options(row.id)))).at(-1).reason.kind, 'stop');
  assert.equal(f.state.calls, adapters.length);
});

test('absent and failed budget producers prevent all adapter dispatch and root creation', async t => {
  const f = await fixture(t);
  await closed(f);
  const policy = await f.policy(true);
  await assert.rejects(policy.await(), /fixture policy startup failed/);
  await closed(f);
  assert.equal(f.state.calls, 0);
});

test('budget unload removes every direct route and the root factory until policy reload', async t => {
  const f = await fixture(t);
  const policy = await f.policy();
  const request = options(adapters[0].id);
  const prepared = await Promise.all(Array.from({ length: 3 }, () => f.ctx.get('llm').prepareCall(request)));
  const stale = prepared[0].stream(request);
  const { agent } = await f.root();
  assert.equal(f.ctx.get('agents').get(agent.id).id, agent.id);
  await policy.dispose();
  await f.tree.await();
  await closed(f);
  assert.equal(f.ctx.get('agents').get(agent.id), undefined);
  assert.equal(f.ctx.get('sessions').get(agent.id), undefined);
  assert.equal(f.state.calls, 0);
  assert.equal(f.tree.resolve(guardRow.id).fiber.state, 2);
  await assert.rejects(collect(prepared[1].stream(request)), /Budget policy.*unavailable/);
  const absent = prepared[2].stream(request);
  f.tree.remove(policyRow.id);
  await f.policy();
  assert.ok(f.ctx.get('agentLoop'));
  await assert.rejects(collect(stale), /Budget policy.*unavailable/);
  await assert.rejects(collect(absent), /Budget policy.*unavailable/);
  assert.equal(f.state.calls, 0);
  assert.equal((await collect(f.ctx.get('llm').stream(options(adapters[0].id)))).at(-1).reason.kind, 'stop');
  assert.equal(f.state.calls, 1);
});

test('policy loss cancels an active root request before provider dispatch and releases its scope', { timeout: 5000 }, async t => {
  const entered = Promise.withResolvers();
  const release = Promise.withResolvers();
  t.after(() => release.resolve());
  const f = await fixture(t);
  const policy = await f.policy();
  const { agent } = await f.root();
  let scopeDisposed = false;
  agent.ctx.effect(() => () => { scopeDisposed = true; });
  f.ctx.on('agent/request', async ({ signal }, next) => { entered.resolve(signal); await release.promise; return next(); });
  send(agent);
  const signal = await entered.promise;
  const aborted = new Promise(resolve => signal.addEventListener('abort', resolve, { once: true }));
  const disposal = policy.dispose();
  await aborted;
  assert.equal(signal.aborted, true);
  assert.equal(f.state.calls, 0);
  release.resolve();
  await disposal;
  await f.tree.await();
  await agent.whenIdle();
  assert.equal(scopeDisposed, true);
  assert.equal(agent.session.snapshotEvents().at(-1).data.reason.kind, 'aborted');
  await closed(f);
  assert.equal(f.state.calls, 0);
});

test('policy loss aborts an already streaming scripted adapter and drains cleanup without another dispatch', { timeout: 5000 }, async t => {
  const f = await fixture(t);
  const policy = await f.policy();
  f.state.hold = true;
  const { agent } = await f.root();
  send(agent);
  const signal = await f.state.started.promise;
  assert.equal(signal.aborted, false);
  await policy.dispose();
  await f.tree.await();
  await agent.whenIdle();
  assert.equal(signal.aborted, true);
  assert.equal(f.state.cleaned, 1);
  assert.equal(f.state.calls, 1);
  await closed(f);
  assert.equal(f.state.calls, 1);
});
