import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { chmod, link, lstat, mkdtemp, realpath, rename, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import test from 'node:test';
import { CheckpointStore, retryConfirmation, validateGraph } from './checkpoint.mjs';

const owner = { rootId: 'root', rootIdentity: 'root-created-123' };
const other = { rootId: 'other', rootIdentity: 'other-created-456' };
const graph = () => ({ nodes: [
  { id: 'first', deps: [], provider: 'mock', model: 'mock-model', prompt: 'first task' },
  { id: 'second', deps: ['first'], provider: 'mock', model: 'mock-model', prompt: 'second task' },
] });
const lock = async fd => {
  try { execFileSync(process.env.DSH_TEST_FLOCK ?? 'flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'ignore', 'ignore', fd] }); }
  catch (error) { if (error.status === 75) error.code = 'EAGAIN'; throw error; }
};

async function fixture(t) {
  const home = await mkdtemp(join(tmpdir(), 'dsh-checkpoint-test-'));
  const stores = [];
  const open = async () => {
    const store = new CheckpointStore(home, lock);
    stores.push(store);
    await store.init();
    return store;
  };
  t.after(async () => {
    for (const store of stores) await store.close();
    assert.equal(await realpath(home), home);
    assert.match(home, /\/dsh-checkpoint-test-[^/]+$/);
    await rm(home, { recursive: true });
  });
  const store = await open();
  const create = (id = 'run', spec = graph()) => store.create({ id, owner, graph: spec, backend: 'spawn', cwd: home });
  return { home, store, open, create };
}

const completed = text => ({ stopReason: 'completed', output: [{ type: 'text', text }] });

test('graph validator refuses code, cycles, duplicate ids, invalid dependencies and unsafe caps', () => {
  assert.equal(validateGraph(graph()).nodes.length, 2);
  assert.throws(() => validateGraph({ ...graph(), script: 'agent(...)' }), /Unknown/);
  assert.throws(() => validateGraph({ nodes: graph().nodes.map(node => ({ ...node, id: 'same' })) }), /duplicate/i);
  assert.throws(() => validateGraph({ nodes: [{ ...graph().nodes[0], deps: ['absent'] }] }), /dependency/i);
  assert.throws(() => validateGraph({ nodes: [{ ...graph().nodes[0], deps: ['second'] }, graph().nodes[1]] }), /cyclic/i);
  assert.throws(() => validateGraph({ ...graph(), maxAttempts: 129 }), /maxAttempts/);
  assert.throws(() => validateGraph({ ...graph(), nodeTimeoutMs: 0 }), /nodeTimeoutMs/);
  assert.throws(() => validateGraph({ nodes: [{ ...graph().nodes[0], prompt: 'x'.repeat(16385) }] }), /prompt/);
});

test('SQLite commits dispatch before execution and persists reusable bounded outputs privately', async t => {
  const { home, store, create } = await fixture(t);
  const created = create();
  assert.equal(created.status, 'draft');
  const lease = await store.claim('run', owner, created.revision, 'start');
  const first = store.dispatch(lease, 'child-first');
  assert.equal(first.node.id, 'first');
  assert.equal(store.snapshot('run', owner).nodes[0].status, 'running');
  store.settle(lease, 'first', 1, completed('durable answer'));
  const second = store.dispatch(lease, 'child-second');
  assert.equal(second.dependencies[0].result.text, 'durable answer');
  store.settle(lease, 'second', 1, completed('界'.repeat(9000)));
  await store.release(lease);
  const snapshot = store.snapshot('run', owner, 'second');
  assert.equal(snapshot.status, 'completed');
  assert.equal(snapshot.nodes[1].result.truncated, true);
  assert.ok(Buffer.byteLength(snapshot.nodes[1].result.text) <= 8192);
  for (const path of [join(home, 'operations'), join(home, 'operations', 'checkpoints-locks')]) assert.equal((await lstat(path)).mode & 0o777, 0o700);
  for (const suffix of ['', '-wal', '-shm']) assert.equal((await lstat(join(home, 'operations', `checkpoints.sqlite${suffix}`))).mode & 0o777, 0o600);
});

test('live owners cannot be stolen; lost dispatch is ambiguous and never replayed on resume', async t => {
  const { store, open, create } = await fixture(t);
  const created = create();
  const lease = await store.claim('run', owner, created.revision, 'start');
  store.dispatch(lease, 'old-child');
  const observer = await open();
  assert.equal(observer.snapshot('run', owner).status, 'running');
  await assert.rejects(observer.claim('run', owner, observer.snapshot('run', owner).revision, 'resume'), /owned|active|busy/i);
  await store.close();
  await observer.recover('run');
  const recovered = observer.snapshot('run', owner);
  assert.equal(recovered.status, 'ambiguous');
  assert.equal(recovered.nodes[0].status, 'ambiguous');
  const resumed = await observer.claim('run', owner, recovered.revision, 'resume');
  assert.equal(observer.dispatch(resumed), null);
  await observer.release(resumed);
  assert.equal(observer.snapshot('run', owner).attemptsStarted, 1);
});

test('retry is revision- and attempt-bound, retains prior child linkage, and creates a new attempt', async t => {
  const { store, create } = await fixture(t);
  const created = create();
  const lease = await store.claim('run', owner, created.revision, 'start');
  store.dispatch(lease, 'charged-child');
  store.ambiguous(lease, 'first', 1, 'capture lost');
  await store.release(lease);
  const snapshot = store.snapshot('run', owner);
  const input = { id: 'run', owner, nodeId: 'first', attempt: 1, revision: snapshot.revision };
  await assert.rejects(store.retry({ ...input, confirmation: 'RETRY run/first/1' }), /confirmation/i);
  await assert.rejects(store.retry({ ...input, revision: snapshot.revision - 1, confirmation: retryConfirmation('run', 'first', 1, snapshot.revision - 1) }), /revision/i);
  const retried = await store.retry({ ...input, confirmation: retryConfirmation('run', 'first', 1, snapshot.revision) });
  assert.equal(retried.nodes[0].attempt, 2);
  assert.equal(retried.nodes[0].attempts[0].childId, 'charged-child');
  assert.equal(retried.nodes[0].attempts[0].status, 'ambiguous');
  assert.equal(retried.attemptsStarted, 1);
  const resumed = await store.claim('run', owner, retried.revision, 'resume');
  const dispatch = store.dispatch(resumed, 'new-child');
  assert.equal(dispatch.attempt, 2);
  store.settle(resumed, 'first', 2, completed('retried output'));
  store.dispatch(resumed, 'dependent');
  store.settle(resumed, 'second', 1, completed('complete'));
  await store.release(resumed);
  assert.equal(store.snapshot('run', owner).attemptsStarted, 3);
});

test('reopened completed dependencies are reused and stale revision transactions do not mutate state', async t => {
  const { store, open, create } = await fixture(t);
  const created = create();
  const lease = await store.claim('run', owner, created.revision, 'start');
  store.dispatch(lease, 'first-child');
  store.settle(lease, 'first', 1, completed('saved'));
  await store.release(lease);
  const before = store.snapshot('run', owner);
  const observer = await open();
  await assert.rejects(observer.claim('run', owner, created.revision, 'resume'), /revision/i);
  assert.deepEqual(observer.snapshot('run', owner), before);
  const resumed = await observer.claim('run', owner, before.revision, 'resume');
  assert.throws(() => store.settle({ ...resumed, token: 'stale' }, 'second', 1, completed('bad')), /lease|owner/i);
  const next = observer.dispatch(resumed, 'second-child');
  assert.equal(next.node.id, 'second');
  assert.equal(next.dependencies[0].result.text, 'saved');
  observer.settle(resumed, 'second', 1, completed('done'));
  await observer.release(resumed);
});

test('cross-root and changed durable root identities cannot read or mutate a run', async t => {
  const { store, create } = await fixture(t);
  const created = create();
  for (const bad of [other, { ...owner, rootIdentity: 'reused-id' }]) {
    assert.throws(() => store.snapshot('run', bad), /owner|root/i);
    await assert.rejects(store.claim('run', bad, created.revision, 'start'), /owner|root/i);
    await assert.rejects(store.cancel('run', bad, created.revision), /owner|root/i);
  }
  assert.equal(store.list(other).length, 0);
});

test('canonical private files reject symlinks, hardlink-style modes and public ledgers', async t => {
  const { home, store } = await fixture(t);
  await store.close();
  await chmod(join(home, 'operations', 'checkpoints.sqlite'), 0o644);
  await assert.rejects(new CheckpointStore(home, lock).init(), /Unsafe/);
  await chmod(join(home, 'operations', 'checkpoints.sqlite'), 0o600);
  const alias = join(home, 'alias');
  await symlink(join(home, 'operations'), alias);
  await assert.rejects(new CheckpointStore(alias, lock).init(), /[Ss]ymlink|canonical/);
  await link(join(home, 'operations', 'checkpoints.sqlite'), join(home, 'database-hardlink'));
  await assert.rejects(new CheckpointStore(home, lock).init(), /Unsafe/);
});

test('committed completed output survives owner death before run release', async t => {
  const { store, open, create } = await fixture(t);
  const created = create('finished', { nodes: [graph().nodes[0]] });
  const lease = await store.claim(created.id, owner, created.revision, 'start');
  store.dispatch(lease, 'completed-child');
  store.settle(lease, 'first', 1, completed('durable before release'));
  await store.close();
  const observer = await open();
  const recovered = observer.snapshot(created.id, owner, 'first');
  assert.equal(recovered.status, 'completed');
  assert.equal(recovered.nodes[0].result.text, 'durable before release');
  await assert.rejects(observer.claim(created.id, owner, recovered.revision, 'resume'), /completed/);
  assert.equal(observer.snapshot(created.id, owner).attemptsStarted, 1);
});

test('simultaneous SQLite instances serialize CAS claims and leave exactly one owner', async t => {
  const { store, open, create } = await fixture(t);
  const created = create();
  const other = await open();
  const claims = await Promise.allSettled([store.claim('run', owner, created.revision, 'start'), other.claim('run', owner, created.revision, 'start')]);
  assert.equal(claims.filter(result => result.status === 'fulfilled').length, 1);
  const index = claims.findIndex(result => result.status === 'fulfilled');
  await [store, other][index].release(claims[index].value);
  assert.equal(store.snapshot('run', owner).attemptsStarted, 0);
});

test('attempt and durable deadline caps survive reopen and cannot be increased by retry', async t => {
  const { store, open, create } = await fixture(t);
  const created = create('capped', { nodes: [graph().nodes[0]], maxAttempts: 1 });
  const lease = await store.claim(created.id, owner, created.revision, 'start');
  store.dispatch(lease, 'charged');
  store.ambiguous(lease, 'first', 1, 'unknown');
  await store.release(lease);
  const observer = await open();
  const snapshot = observer.snapshot(created.id, owner);
  await assert.rejects(observer.retry({ id: created.id, owner, nodeId: 'first', attempt: 1, revision: snapshot.revision, confirmation: retryConfirmation(created.id, 'first', 1, snapshot.revision) }), /cap/);
  const expiring = create('deadline', { nodes: [graph().nodes[0]], runTimeoutMs: 100 });
  const active = await store.claim(expiring.id, owner, expiring.revision, 'start');
  await store.release(active);
  const originalNow = Date.now;
  try {
    Date.now = () => originalNow() + 1000;
    const expired = observer.snapshot(expiring.id, owner);
    await assert.rejects(observer.claim(expiring.id, owner, expired.revision, 'resume'), /deadline/);
  } finally { Date.now = originalNow; }
});

test('replacing a live lease path blocks dispatch without changing the database', async t => {
  const { store, create } = await fixture(t);
  const created = create();
  const lease = await store.claim('run', owner, created.revision, 'start');
  assert.equal(await realpath(lease.path), lease.path);
  assert.match(lease.path, /\/checkpoints-locks\/[a-f0-9]{64}\.lock$/);
  await rename(lease.path, `${lease.path}.old`);
  await symlink(`${lease.path}.old`, lease.path);
  assert.throws(() => store.dispatch(lease), /Unsafe|ownership/);
  assert.equal(store.snapshot('run', owner).attemptsStarted, 0);
});

test('OS process death releases the stable lease but leaves running work ambiguous', async t => {
  const { home, store } = await fixture(t);
  const script = `import { CheckpointStore } from ${JSON.stringify(new URL('./checkpoint.mjs', import.meta.url).href)};
import { execFileSync } from 'node:child_process';
const lock = async fd => { try { execFileSync(process.env.DSH_TEST_FLOCK ?? 'flock', ['--exclusive','--nonblock','--conflict-exit-code','75','3'], {stdio:['ignore','ignore','ignore',fd]}); } catch(e) {if(e.status===75)e.code='EAGAIN';throw e;} };
const store = new CheckpointStore(process.argv[1], lock); await store.init();
const owner=${JSON.stringify(owner)}; const row=store.create({id:'crash',owner,graph:${JSON.stringify(graph())},backend:'spawn',cwd:process.argv[1]});
const lease=await store.claim('crash',owner,row.revision,'start');store.dispatch(lease,'orphan-child');process.stdout.write('ready\\n');setInterval(()=>{},1000);`;
  const child = spawn(process.execPath, ['--input-type=module', '-e', script, home], { stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); });
  const exited = once(child, 'exit');
  const first = await Promise.race([once(child.stdout, 'data'), exited.then(() => { throw new Error('child exited before lease'); })]);
  assert.match(first[0].toString(), /ready/);
  await store.recover('crash');
  assert.equal(store.snapshot('crash', owner).status, 'running');
  child.kill('SIGKILL');
  assert.equal((await exited)[1], 'SIGKILL');
  await store.recover('crash');
  assert.equal(store.snapshot('crash', owner).nodes[0].status, 'ambiguous');
});
