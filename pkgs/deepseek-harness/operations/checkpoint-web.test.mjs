import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { CheckpointStore } from './checkpoint.mjs';
import { CheckpointRunner, checkpointToolOptions, rootOwner } from './checkpoint-runner.mjs';
import { registerCheckpointRoutes } from './checkpoint-web.mjs';

const lock = async fd => {
  try { execFileSync(process.env.DSH_TEST_FLOCK ?? 'flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'ignore', 'ignore', fd] }); }
  catch (error) { if (error.status === 75) error.code = 'EAGAIN'; throw error; }
};
const graph = { nodes: [{ id: 'a', deps: [], provider: 'mock', model: 'mock', prompt: 'private task' }] };
function deferred() { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; }

async function fixture(t) {
  const home = await mkdtemp(join(tmpdir(), 'dsh-checkpoint-web-'));
  const store = await new CheckpointStore(home, lock).init();
  const parent = { id: 'root', session: { id: 'root', header: { id: 'root', createdAt: 1, isSeeded: false } }, ctx: { effect: () => () => {} } };
  const other = { ...parent, id: 'other', session: { id: 'other', header: { id: 'other', createdAt: 2, isSeeded: false } } };
  const registry = new Map([[parent.id, parent], [other.id, other]]);
  const routes = new Map();
  let calls = 0;
  const backend = { capabilities: { agentOptions: true, depthLimit: true }, prepareContinuable() {} };
  const ctx = {
    agents: { get: id => registry.get(id), list: () => [...registry.values()] },
    workingDirectory: { get: () => home },
    llm: { resolveCallConfig: async route => route },
    sessionProjections: { stateOf: () => [{ provider: 'mock', model: 'mock' }] },
    subagents: { getProvider: () => backend, resolveMaxDepth: () => 1, startActivation: async spec => { calls++; return { childId: spec.childId, result: Promise.resolve({ stopReason: 'completed', output: [{ type: 'text', text: 'private output' }] }), dispose: async () => {} }; } },
    get: name => name === 'approval' ? { request: async () => 'rejected' } : undefined,
    effect: fn => fn(),
    connection: { fetch: { register: route => { routes.set(route.path, route); return () => {}; } } },
  };
  const runner = new CheckpointRunner(ctx, store);
  registerCheckpointRoutes(ctx, runner);
  const identity = rootOwner(ctx, parent).rootIdentity;
  const base = { action: 'create', id: 'run', ownerSessionId: parent.id, ownerIdentity: identity, graph, confirmation: 'CREATE CHECKPOINT root 0' };
  const request = (input, headers = {}, signal) => new Request('https://dsh.invalid/api/operations/checkpoints/action', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dsh-operations': '1', origin: 'https://dsh.invalid', ...headers }, body: JSON.stringify(input), signal });
  const post = (input, headers, signal) => routes.get('/api/operations/checkpoints/action').fetch(request(input, headers, signal));
  t.after(async () => {
    await runner.close();
    assert.equal(await realpath(home), home);
    assert.match(home, /\/dsh-checkpoint-web-[^/]+$/);
    await rm(home, { recursive: true });
  });
  return { store, runner, parent, other, ctx, registry, routes, post, base, calls: () => calls };
}

test('browser actions require origin, custom header, identity and exact typed phrase', async t => {
  const { post, base, calls, runner, parent } = await fixture(t);
  assert.equal((await post(base, { origin: 'https://evil.invalid' })).status, 403);
  assert.equal((await post(base, { origin: '' })).status, 403);
  assert.equal((await post(base, { 'sec-fetch-site': 'cross-site' })).status, 403);
  assert.equal((await post(base, { 'x-dsh-operations': '0' })).status, 403);
  assert.equal((await post({ ...base, confirmation: 'yes' })).status, 400);
  assert.equal((await post({ ...base, approved: true })).status, 400);
  assert.equal((await post({ ...base, ownerIdentity: 'stale' })).status, 409);
  assert.equal(calls(), 0);
  assert.equal((await runner.status(undefined, parent)).runs.length, 0);
});

test('explicit authenticated human action works without changing never-approval tool policy', async t => {
  const { post, base, calls, runner, parent, routes } = await fixture(t);
  const createdResponse = await post(base);
  assert.equal(createdResponse.status, 200);
  const created = await createdResponse.json();
  assert.equal(created.authorization.actor, 'authenticated-operator');
  assert.equal(calls(), 0);
  const tool = checkpointToolOptions(runner);
  await assert.rejects(tool.execute({ action: 'start', id: created.id, revision: created.revision }, { agent: parent, callId: 'call', signal: new AbortController().signal }), /approval rejected/);
  const response = await post({ action: 'start', ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity, id: created.id, revision: created.revision, confirmation: `START CHECKPOINT ${created.id} ${created.revision}` });
  assert.equal(response.status, 200);
  await runner.wait(created.id);
  assert.equal(calls(), 1);
  const listing = await (await routes.get('/api/operations/checkpoints').fetch(new Request('https://dsh.invalid/api/operations/checkpoints'))).json();
  assert.equal(listing.roots[0].identity, base.ownerIdentity);
  assert.doesNotMatch(JSON.stringify(listing), /private task|private output/);
  const query = new URLSearchParams({ id: created.id, ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity, nodeId: 'a' });
  const status = await (await routes.get('/api/operations/checkpoints').fetch(new Request(`https://dsh.invalid/api/operations/checkpoints?${query}`))).json();
  assert.equal(status.nodes[0].result.text, 'private output');
});

test('synthetic HTTP bridge URL uses preserved Host, not forwarded or synthetic origin', async t => {
  const { base, routes, calls } = await fixture(t);
  const route = routes.get('/api/operations/checkpoints/action');
  const request = (origin, host = 'citrus.tail1e65cd.ts.net') => new Request('http://dsh.internal/api/operations/checkpoints/action', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-dsh-operations': '1', origin, host, 'x-forwarded-host': 'evil.invalid' }, body: JSON.stringify(base),
  });
  for (const origin of ['https://evil.invalid', 'https://citrus.tail1e65cd.ts.net/path', 'https://user@citrus.tail1e65cd.ts.net', 'null']) assert.equal((await route.fetch(request(origin))).status, 403);
  assert.equal((await route.fetch(request('https://citrus.tail1e65cd.ts.net'))).status, 200);
  assert.equal(calls(), 0);
});

test('operator audit records commit with successful mutation but never failed CAS', async t => {
  const { post, base, store, ctx, parent, runner } = await fixture(t);
  const created = await (await post(base)).json();
  const owner = rootOwner(ctx, parent);
  assert.deepEqual(store.actions(created.id, owner).map(row => [row.action, row.actor, row.priorRevision]), [['create', 'authenticated-operator', null]]);
  const cancelled = await post({ action: 'cancel', id: created.id, revision: created.revision, confirmation: `CANCEL CHECKPOINT ${created.id} ${created.revision}`, ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity });
  assert.equal(cancelled.status, 200);
  const failed = await post({ action: 'start', id: created.id, revision: created.revision, confirmation: `START CHECKPOINT ${created.id} ${created.revision}`, ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity });
  assert.equal(failed.status, 409);
  const rows = store.actions(created.id, owner);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(row => row.action), ['create', 'cancel']);
  assert.doesNotMatch(JSON.stringify(rows), /private task|CHECKPOINT root/);
  const before = await runner.status(created.id, parent);
  await assert.rejects(store.cancel(created.id, owner, before.revision, undefined, () => ({ actor: 'forged', rootId: owner.rootId, action: 'cancel' })), /audit authorization/);
  assert.equal((await runner.status(created.id, parent)).revision, before.revision);
  assert.equal(store.actions(created.id, owner).length, 2);
});

test('human cross-root and stale revision requests cannot control a selected run', async t => {
  const { post, base, runner, other, ctx, calls } = await fixture(t);
  const created = await (await post(base)).json();
  const input = { action: 'start', id: created.id, revision: created.revision, confirmation: `START CHECKPOINT ${created.id} ${created.revision}`, ownerSessionId: other.id, ownerIdentity: rootOwner(ctx, other).rootIdentity };
  assert.equal((await post(input)).status, 409);
  const cancelled = await runner.cancel(created.id, created.revision, ctx.agents.get(base.ownerSessionId));
  assert.equal(cancelled.status, 'cancelled');
  assert.equal((await post({ ...input, ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity })).status, 409);
  assert.equal(calls(), 0);
});

test('human mutation refuses parent replacement while waiting for OS lease', async t => {
  const { post, base, store, parent, registry, ctx } = await fixture(t);
  const created = await (await post(base)).json();
  const acquired = deferred();
  const release = deferred();
  const original = store.lockExclusive;
  store.lockExclusive = async fd => { await original(fd); acquired.resolve(); await release.promise; };
  const response = post({ action: 'cancel', id: created.id, revision: created.revision, confirmation: `CANCEL CHECKPOINT ${created.id} ${created.revision}`, ownerSessionId: base.ownerSessionId, ownerIdentity: base.ownerIdentity });
  await acquired.promise;
  registry.set(parent.id, { ...parent });
  release.resolve();
  assert.equal((await response).status, 409);
  store.lockExclusive = original;
  assert.equal(store.snapshot(created.id, rootOwner(ctx, ctx.agents.get(parent.id))).revision, created.revision);
});
