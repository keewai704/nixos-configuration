import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { CheckpointStore, retryConfirmation } from './checkpoint.mjs';
import { CheckpointRunner, checkpointToolOptions, rootOwner } from './checkpoint-runner.mjs';

const graph = () => ({ nodes: [
  { id: 'a', deps: [], provider: 'mock-llm', model: 'mock-model', prompt: 'first prompt' },
  { id: 'b', deps: ['a'], provider: 'mock-llm', model: 'mock-model', prompt: 'second prompt' },
] });
const done = text => ({ stopReason: 'completed', output: [{ type: 'text', text }] });
const lock = async fd => {
  try { execFileSync(process.env.DSH_TEST_FLOCK ?? 'flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'ignore', 'ignore', fd] }); }
  catch (error) { if (error.status === 75) error.code = 'EAGAIN'; throw error; }
};
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

async function fixture(t, start, local = true) {
  const home = await mkdtemp(join(tmpdir(), 'dsh-checkpoint-runner-'));
  const store = new CheckpointStore(home, lock);
  await store.init();
  const calls = [];
  const approvals = [];
  const effects = [];
  const parent = { id: 'root', session: { id: 'root', header: { id: 'root', createdAt: 123, isSeeded: false } }, ctx: { effect: fn => { effects.push(fn()); return () => {}; } } };
  const registry = new Map([[parent.id, parent]]);
  const backend = { capabilities: { agentOptions: true, depthLimit: true }, ...(local ? { prepareContinuable: () => {} } : {}) };
  const ctx = {
    llm: { resolveCallConfig: async (route, signal) => { signal.throwIfAborted(); return route; } },
    sessionProjections: { stateOf: () => [{ provider: 'mock-llm', model: 'mock-model' }] },
    agents: { get: id => registry.get(id) },
    workingDirectory: { get: () => home },
    subagents: {
      getProvider: () => backend,
      resolveMaxDepth: () => 1,
      startActivation: async spec => {
        calls.push(spec);
        return start ? start(spec, calls.length) : { childId: spec.childId ?? `external-${calls.length}`, result: Promise.resolve(done(`answer ${calls.length}`)), dispose: async () => {} };
      },
    },
    get: name => name === 'approval' ? { request: async request => { approvals.push(request); return 'allowed-once'; } } : undefined,
  };
  const runner = new CheckpointRunner(ctx, store);
  t.after(async () => {
    await runner.close();
    assert.equal(await realpath(home), home);
    assert.match(home, /\/dsh-checkpoint-runner-[^/]+$/);
    await rm(home, { recursive: true });
  });
  const create = (id = 'run', spec = graph()) => runner.create({ id, graph: spec }, parent);
  return { home, store, ctx, runner, parent, calls, approvals, registry, effects, create };
}

test('native runner uses exact live parent, caller delivery, reserved local ids and durable DAG outputs', async t => {
  const { runner, parent, calls, create } = await fixture(t);
  const created = await create();
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  const result = await runner.status(created.id, parent, 'b');
  assert.equal(result.status, 'completed');
  assert.equal(result.nodes[1].result.text, 'answer 2');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].request.parent, parent);
  assert.equal(calls[0].delivery, 'caller');
  assert.ok(calls[0].childId);
  assert.deepEqual(calls[0].request.agentOptions, { provider: 'mock-llm', model: 'mock-model' });
  assert.equal(calls[0].request.maxDepth, 1);
  assert.match(calls[1].request.prompt[0].text, /answer 1/);
  assert.match(calls[1].request.prompt[0].text, /untrusted/i);
});

test('cancelled creation during directory resolution does not persist a draft', async t => {
  const { runner, parent } = await fixture(t);
  const controller = new AbortController();
  const pending = runner.create({ id: 'cancelled-create', graph: graph() }, parent, controller.signal);
  controller.abort();
  await assert.rejects(pending, /aborted/i);
  assert.equal((await runner.status(undefined, parent)).runs.length, 0);
});

test('normal PTC receipt settlement does not cancel accepted background work', async t => {
  const started = deferred();
  const finish = deferred();
  let disposals = 0;
  const { runner, parent, create } = await fixture(t, async spec => {
    started.resolve();
    return { childId: spec.childId, result: finish.promise, dispose: async () => { disposals++; } };
  });
  const created = await create('ptc', { nodes: [graph().nodes[0]] });
  const ptc = new AbortController();
  await runner.activate('start', created.id, created.revision, parent, ptc.signal);
  ptc.abort(new Error('run_code settled'));
  await started.promise;
  assert.equal(disposals, 0);
  finish.resolve(done('completed after receipt'));
  await runner.wait(created.id);
  assert.equal((await runner.status(created.id, parent)).status, 'completed');
});

test('depth and selected model policy are reevaluated before every node, leaving blocked work pending', async t => {
  const { runner, parent, ctx, create, calls } = await fixture(t);
  let depth = 1;
  const originalStart = ctx.subagents.startActivation;
  ctx.subagents.resolveMaxDepth = () => depth;
  ctx.subagents.startActivation = async spec => { const result = await originalStart(spec); depth = 0; return result; };
  const created = await create();
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  const paused = await runner.status(created.id, parent);
  assert.equal(paused.nodes[0].status, 'completed');
  assert.equal(paused.nodes[1].status, 'pending');
  assert.equal(paused.attemptsStarted, 1);
  assert.equal(calls.length, 1);
  depth = 1;
  ctx.sessionProjections.stateOf = () => [{ provider: 'different', model: 'route' }];
  await runner.activate('resume', created.id, paused.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  assert.equal((await runner.status(created.id, parent)).attemptsStarted, 1);
  const current = await runner.status(created.id, parent);
  ctx.sessionProjections.stateOf = () => null;
  parent.options = { provider: 'mock-llm', model: 'mock-model' };
  await runner.activate('resume', created.id, current.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  assert.equal(calls.length, 2);
  assert.equal((await runner.status(created.id, parent)).status, 'completed');
});

test('external backends allocate child ids and completion awaits exact activation disposal', async t => {
  const disposed = deferred();
  const disposalStarted = deferred();
  const { runner, parent, calls, create } = await fixture(t, async () => ({ childId: 'external', result: Promise.resolve(done('external answer')), dispose: async () => { disposalStarted.resolve(); await disposed.promise; } }), false);
  const created = await create('external', { nodes: [graph().nodes[0]] });
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await disposalStarted.promise;
  assert.equal((await runner.status(created.id, parent)).nodes[0].status, 'running');
  assert.equal(Object.hasOwn(calls[0], 'childId'), false);
  disposed.resolve();
  await runner.wait(created.id);
  assert.equal((await runner.status(created.id, parent)).nodes[0].attempts[0].childId, 'external');
});

test('cold root resumes pending nodes using outputs and never restarts completed nodes', async t => {
  const { runner, store, ctx, parent, registry, calls, create } = await fixture(t);
  const created = await create();
  const owner = rootOwner(ctx, parent);
  const lease = await store.claim(created.id, owner, created.revision, 'start');
  store.dispatch(lease, 'prior-child');
  store.settle(lease, 'a', 1, done('recovered output'));
  await store.release(lease);
  const cold = { ...parent, session: { ...parent.session, header: { ...parent.session.header } } };
  registry.set(parent.id, cold);
  const snapshot = await runner.status(created.id, cold);
  await runner.activate('resume', created.id, snapshot.revision, cold, new AbortController().signal);
  await runner.wait(created.id);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].request.parent, cold);
  assert.match(calls[0].request.prompt[0].text, /recovered output/);
  await assert.rejects(runner.status(created.id, parent), /live parent/);
});

test('timeout disposes published activation and preserves ambiguous work without automatic replay', async t => {
  const started = deferred();
  let disposed = 0;
  const { runner, parent, create, calls } = await fixture(t, async spec => {
    const result = deferred();
    started.resolve();
    return { childId: spec.childId, result: result.promise, dispose: async () => { disposed++; result.resolve(done('late success')); } };
  });
  const created = await create('timeout', { ...graph(), nodeTimeoutMs: 100 });
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await started.promise;
  await runner.wait(created.id);
  const status = await runner.status(created.id, parent);
  assert.equal(status.status, 'ambiguous');
  assert.equal(disposed, 1);
  await runner.activate('resume', created.id, status.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  assert.equal(calls.length, 1);
});

test('runner shutdown awaits startup, result and child disposal before releasing ownership', async t => {
  const opening = deferred();
  const startup = deferred();
  const cleanup = deferred();
  const result = deferred();
  let closed = false;
  let disposed = false;
  const { runner, parent, store, create } = await fixture(t, async spec => {
    opening.resolve();
    await startup.promise;
    return { childId: spec.childId, result: result.promise, dispose: async () => { disposed = true; result.resolve(done('stopped')); await cleanup.promise; } };
  });
  const created = await create();
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await opening.promise;
  const closing = runner.close().then(() => { closed = true; });
  await Promise.resolve();
  assert.equal(closed, false);
  startup.resolve();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(disposed, true);
  assert.equal(closed, false);
  assert.equal(store.snapshot(created.id, rootOwner(runner.ctx, parent)).nodes[0].status, 'running');
  cleanup.resolve();
  await closing;
  assert.equal(closed, true);
});

test('tool actions require current explicit approval and refuse stale, descendant and cross-root callers', async t => {
  const { ctx, runner, parent, approvals, calls, registry } = await fixture(t);
  const tool = checkpointToolOptions(runner);
  const exec = { agent: parent, signal: new AbortController().signal, callId: 'call-1' };
  ctx.get = () => ({ request: async () => 'rejected' });
  await assert.rejects(tool.execute({ action: 'create', id: 'no', graph: graph() }, exec), /approval/i);
  assert.equal((await runner.status(undefined, parent)).runs.length, 0);
  ctx.get = () => ({ request: async request => { approvals.push(request); return 'allowed-once'; } });
  const created = await tool.execute({ action: 'create', id: 'yes', graph: graph() }, exec);
  await assert.rejects(tool.execute({ action: 'start', id: 'yes', revision: 0 }, exec), /revision/);
  await tool.execute({ action: 'start', id: 'yes', revision: created.revision }, exec);
  await runner.wait('yes');
  assert.equal(approvals.length, 2);
  assert.equal(approvals[1].agent, parent);
  assert.match(approvals[1].reason, /yes/);
  assert.match(approvals[1].reason, /mock-llm\/mock-model/);
  assert.match(approvals[1].reason, /first prompt/);
  assert.equal(calls.length, 2);
  const other = { ...parent, id: 'other', session: { id: 'other', header: { id: 'other', createdAt: 234, isSeeded: false } } };
  registry.set(other.id, other);
  await assert.rejects(tool.execute({ action: 'status', id: 'yes' }, { ...exec, agent: other }), /owner/);
  const child = { ...parent, id: 'child', session: { id: 'child', header: { id: 'child', createdAt: 234, origin: 'subagent', parentSession: 'root', delegationDepth: 1 } } };
  registry.set(child.id, child);
  await assert.rejects(tool.execute({ action: 'create', graph: graph() }, { ...exec, agent: child }), /root/);
});

test('retry tools require exact confirmation and another explicit resume approval', async t => {
  const { store, runner, ctx, parent, create, calls, approvals } = await fixture(t);
  const created = await create();
  const owner = rootOwner(ctx, parent);
  const lease = await store.claim(created.id, owner, created.revision, 'start');
  store.dispatch(lease, 'old-charged');
  store.ambiguous(lease, 'a', 1, 'lost');
  await store.release(lease);
  const tool = checkpointToolOptions(runner);
  const exec = { agent: parent, signal: new AbortController().signal, callId: 'call-retry' };
  const snapshot = await runner.status(created.id, parent);
  const args = { action: 'retry', id: created.id, revision: snapshot.revision, nodeId: 'a', attempt: 1, confirmation: retryConfirmation(created.id, 'a', 1, snapshot.revision) };
  const retried = await tool.execute(args, exec);
  assert.equal(calls.length, 0);
  assert.equal(retried.nodes[0].attempts[0].childId, 'old-charged');
  await tool.execute({ action: 'resume', id: created.id, revision: retried.revision }, exec);
  await runner.wait(created.id);
  assert.equal(approvals.length, 2);
  assert.equal(calls.length, 2);
});

test('approval races recheck the revision and durable current parent before any dispatch', async t => {
  const { runner, parent, ctx, registry, create, calls } = await fixture(t);
  const tool = checkpointToolOptions(runner);
  const created = await create();
  const exec = { agent: parent, signal: new AbortController().signal, callId: 'racing-call' };
  ctx.get = () => ({ request: async () => {
    await runner.cancel(created.id, created.revision, parent);
    return 'allowed-once';
  } });
  await assert.rejects(tool.execute({ action: 'start', id: created.id, revision: created.revision }, exec), /revision/);
  const another = await create('another');
  ctx.get = () => ({ request: async () => {
    registry.set(parent.id, { ...parent });
    return 'allowed-once';
  } });
  await assert.rejects(tool.execute({ action: 'start', id: another.id, revision: another.revision }, exec), /live parent/);
  assert.equal(calls.length, 0);
});

test('retry and cancel revalidate live caller and signal inside the leased transaction', async t => {
  const { runner, store, ctx, parent, registry, create } = await fixture(t);
  const owner = rootOwner(ctx, parent);
  const created = await create();
  const lease = await store.claim(created.id, owner, created.revision, 'start');
  store.dispatch(lease, 'prior-child');
  store.ambiguous(lease, 'a', 1, 'lost result');
  await store.release(lease);
  const initial = store.snapshot(created.id, owner);
  for (const action of ['retry', 'cancel']) {
    for (const change of ['replace', 'dispose', 'abort']) {
      registry.set(parent.id, parent);
      const acquired = deferred();
      const continueLease = deferred();
      const original = store.lockExclusive;
      store.lockExclusive = async fd => { await original(fd); acquired.resolve(); await continueLease.promise; };
      const controller = new AbortController();
      const operation = action === 'retry'
        ? runner.retry({ id: created.id, nodeId: 'a', attempt: 1, revision: initial.revision, confirmation: retryConfirmation(created.id, 'a', 1, initial.revision) }, parent, controller.signal)
        : runner.cancel(created.id, initial.revision, parent, controller.signal);
      const rejected = assert.rejects(operation, /live parent|aborted/i);
      await acquired.promise;
      if (change === 'replace') registry.set(parent.id, { ...parent });
      if (change === 'dispose') registry.delete(parent.id);
      if (change === 'abort') controller.abort();
      continueLease.resolve();
      await rejected;
      store.lockExclusive = original;
      assert.deepEqual(store.snapshot(created.id, owner), initial);
    }
  }
  registry.set(parent.id, parent);
});

test('same durable root cannot cancel a run still owned by another exact parent object', async t => {
  const started = deferred();
  const { runner, parent, store, ctx, registry, create } = await fixture(t, async spec => {
    const result = deferred();
    started.resolve();
    return { childId: spec.childId, result: result.promise, dispose: async () => result.resolve(done('stopped')) };
  });
  const created = await create();
  const owner = rootOwner(ctx, parent);
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await started.promise;
  await new Promise(resolve => setImmediate(resolve));
  const before = store.snapshot(created.id, owner);
  const replacement = { ...parent };
  registry.set(parent.id, replacement);
  await assert.rejects(runner.cancel(created.id, before.revision, replacement), /exact live parent/);
  assert.deepEqual(store.snapshot(created.id, owner), before);
});

test('parent disposal drains active children and leaves no executable background owner', async t => {
  const started = deferred();
  let disposals = 0;
  const { runner, parent, effects, create, calls } = await fixture(t, async spec => {
    const result = deferred();
    started.resolve();
    return { childId: spec.childId, result: result.promise, dispose: async () => { disposals++; result.resolve(done('late')); } };
  });
  const created = await create();
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await started.promise;
  await effects[0]();
  assert.equal(disposals, 1);
  assert.equal(calls.length, 1);
  assert.equal(runner.active.size, 0);
  assert.equal((await runner.status(created.id, parent)).status, 'ambiguous');
});

test('activation and teardown rejections are ambiguous and never retried automatically', async t => {
  const { runner, parent, create, calls } = await fixture(t, async (spec, count) => {
    if (count === 1) throw new Error('dispatch outcome unknown');
    return { childId: spec.childId, result: Promise.resolve(done('captured')), dispose: async () => { throw new Error('teardown failed'); } };
  });
  const first = await create('start-failure', { nodes: [graph().nodes[0]] });
  await runner.activate('start', first.id, first.revision, parent, new AbortController().signal);
  await runner.wait(first.id);
  assert.equal((await runner.status(first.id, parent)).status, 'ambiguous');
  const second = await create('teardown-failure', { nodes: [graph().nodes[0]] });
  await runner.activate('start', second.id, second.revision, parent, new AbortController().signal);
  await runner.wait(second.id);
  assert.equal((await runner.status(second.id, parent)).status, 'ambiguous');
  assert.equal(calls.length, 2);
});

test('active run cap includes in-flight lease admissions and schema refuses arbitrary continuation', async t => {
  const { runner, parent, create } = await fixture(t);
  runner.maxActiveRuns = 1;
  const first = await create('one');
  const second = await create('two');
  const firstStart = runner.activate('start', first.id, first.revision, parent, new AbortController().signal);
  await assert.rejects(runner.activate('start', second.id, second.revision, parent, new AbortController().signal), /cap/);
  await firstStart;
  await runner.wait(first.id);
  const tool = checkpointToolOptions(runner);
  await assert.rejects(tool.execute({ action: 'create', graph: graph(), script: 'arbitrary JS' }, { agent: parent, signal: new AbortController().signal }), /unknown/);
});

test('cancellation is revision-bound, drains the active child, and prevents new dispatch', async t => {
  const started = deferred();
  const { runner, parent, create, calls } = await fixture(t, async spec => {
    const result = deferred();
    started.resolve();
    return { childId: spec.childId, result: result.promise, dispose: async () => result.resolve({ stopReason: 'aborted', output: [] }) };
  });
  const created = await create();
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await started.promise;
  await new Promise(resolve => setImmediate(resolve));
  const snapshot = await runner.status(created.id, parent);
  const result = await runner.cancel(created.id, snapshot.revision, parent);
  assert.equal(result.status, 'cancelled');
  assert.equal(calls.length, 1);
});
