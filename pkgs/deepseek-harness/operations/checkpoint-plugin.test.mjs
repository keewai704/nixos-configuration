import assert from 'node:assert/strict';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire, registerHooks } from 'node:module';
import { pathToFileURL } from 'node:url';
import test from 'node:test';

const required = createRequire(import.meta.url);
const external = process.env.DSH_CHECKPOINT_TEST_MODULES ? createRequire(pathToFileURL(join(process.env.DSH_CHECKPOINT_TEST_MODULES, '_checkpoint_test.cjs'))) : required;
let dependencies = true;
try { external.resolve('@deepseek-ai/dsh-tools'); external.resolve('@deepseek-ai/schemastery'); }
catch { dependencies = false; }

test('public plugin mounts its actual tool and metadata-only route, with awaited disposal', { skip: !dependencies && 'DSH kernel dependencies absent; provide DSH_CHECKPOINT_TEST_MODULES for integration validation' }, async t => {
  const home = await mkdtemp(join(tmpdir(), 'dsh-checkpoint-plugin-'));
  const hooks = registerHooks({ resolve(specifier, context, next) {
    if (specifier === '@deepseek-ai/dsh-home-paths') return { url: `data:text/javascript,${encodeURIComponent(`export const resolveDshHome = () => ${JSON.stringify(home)};`)}`, shortCircuit: true };
    if (specifier.startsWith('@deepseek-ai/')) {
      try { return { url: pathToFileURL(external.resolve(specifier)).href, shortCircuit: true }; }
      catch { return next(specifier, context); }
    }
    return next(specifier, context);
  } });
  const effects = [];
  const tools = new Map();
  const routes = new Map();
  const services = new Map();
  const parent = { id: 'plugin-root', session: { id: 'plugin-root', header: { id: 'plugin-root', createdAt: 123, isSeeded: false } }, ctx: { effect: fn => { effects.push(fn()); return () => {}; } } };
  const backend = { capabilities: { agentOptions: true, depthLimit: true }, prepareContinuable() {} };
  let starts = 0;
  const ctx = {
    llm: { resolveCallConfig: async route => route },
    sessionProjections: { stateOf: () => [{ provider: 'mock', model: 'mock' }] },
    effect: fn => { effects.push(fn()); return () => {}; },
    provide: (name, value) => services.set(name, value),
    inject: (_needs, callback) => callback(ctx),
    agents: { get: id => id === parent.id ? parent : undefined, list: () => [parent] },
    tools: { register: tool => { tools.set(tool.name, tool); return () => tools.delete(tool.name); } },
    connection: { fetch: { register: route => { routes.set(route.path, route); return () => routes.delete(route.path); } } },
    workingDirectory: { get: () => home },
    subagents: {
      getProvider: () => backend,
      resolveMaxDepth: () => 1,
      startActivation: async spec => { starts++; return { childId: spec.childId, result: Promise.resolve({ stopReason: 'completed', output: [{ type: 'text', text: 'private result' }] }), dispose: async () => {} }; },
    },
    get: name => name === 'approval' ? { request: async () => 'allowed-once' } : services.get(name),
  };
  t.after(async () => {
    for (const dispose of effects.reverse()) await dispose?.();
    hooks.deregister();
    assert.equal(await realpath(home), home);
    assert.match(home, /\/dsh-checkpoint-plugin-[^/]+$/);
    await rm(home, { recursive: true });
  });
  const plugin = await import('./checkpoint-plugin.mjs');
  assert.ok(plugin.Config);
  assert.ok(plugin.inject.includes('subagents'));
  await plugin.apply(ctx);
  assert.equal(tools.size, 0);
  ctx.checkpoints = services.get('checkpoints');
  const toolsPlugin = await import('./checkpoint-tools.mjs');
  assert.deepEqual(toolsPlugin.inject, ['tools', 'checkpoints']);
  toolsPlugin.apply(ctx);
  const tool = tools.get('checkpoint');
  assert.equal(tool.name, 'checkpoint');
  const exec = { agent: parent, callId: 'call-1', signal: new AbortController().signal };
  await assert.rejects(tool.execute({ action: 'unsupported' }, exec), /action|enum/);
  const created = await tool.execute({ action: 'create', id: 'plugin-run', graph: { nodes: [{ id: 'node', deps: [], provider: 'mock', model: 'mock', prompt: 'private prompt' }] } }, exec);
  await tool.execute({ action: 'start', id: created.id, revision: created.revision }, exec);
  await services.get('checkpoints').wait(created.id);
  const status = await tool.execute({ action: 'status', id: created.id, nodeId: 'node' }, exec);
  assert.equal(status.status, 'completed');
  assert.equal(starts, 1);
  assert.match(JSON.stringify(tool.output.render({}, status)), /private result/);
  const route = routes.get('/api/operations/checkpoints');
  assert.deepEqual(route.methods, ['GET']);
  const response = await route.fetch(new Request('https://dsh.invalid/api/operations/checkpoints'));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const body = await response.text();
  assert.match(body, /plugin-run/);
  assert.doesNotMatch(body, /private prompt|private result|"cwd"|"childId"/);
  assert.equal((await route.fetch(new Request('https://dsh.invalid/api/operations/checkpoints', { method: 'POST' }))).status, 405);
});
