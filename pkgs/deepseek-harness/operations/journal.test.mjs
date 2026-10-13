import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { WorkflowJournal } from './journal.mjs';

const lock = async fd => {
  try { execFileSync(process.env.DSH_TEST_FLOCK ?? 'flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'ignore', 'ignore', fd] }); }
  catch (error) { if (error.status === 75) error.code = 'EAGAIN'; throw error; }
};
const record = id => ({ id, parentSessionId: 'parent', name: 'unit', startedAt: 1000, deadlineAt: 61000, maxTotalAgents: 4, maxConcurrentAgents: 2 });

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'dsh-journal-test-'));
  const journal = new WorkflowJournal(root, lock);
  await journal.init();
  t.after(async () => {
    await journal.close();
    assert.equal(await realpath(root), root);
    assert.match(root, /\/dsh-journal-test-[^/]+$/);
    await rm(root, { recursive: true });
  });
  return { root, journal };
}

test('durably admits, counts and finishes without persisting scripts or prompts', async t => {
  const { root, journal } = await fixture(t);
  await journal.start({ ...record('a'), script: 'secret', prompt: 'secret' });
  await journal.update({ id: 'a', agentsStarted: 2, activeAgents: 1 });
  await journal.finish({ id: 'a', agentsStarted: 2, stopReason: 'completed', finishedAt: 2000 });
  assert.deepEqual((await journal.list()).map(row => [row.status, row.agentsStarted, row.activeAgents]), [['completed', 2, 0]]);
  const file = (await readdir(root)).find(name => name.endsWith('.json'));
  assert.equal((await readFile(join(root, file), 'utf8')).includes('secret'), false);
});

test('refuses duplicate ids, invalid limits, nonmonotone counts and overbudget updates', async t => {
  const { journal } = await fixture(t);
  await assert.rejects(journal.start({ ...record('invalid'), deadlineAt: 0 }), /limits/);
  await journal.start(record('a'));
  await assert.rejects(journal.start(record('a')), /already active/);
  await journal.update({ id: 'a', agentsStarted: 2, activeAgents: 2 });
  await assert.rejects(journal.update({ id: 'a', agentsStarted: 5, activeAgents: 1 }), /budget/);
  await assert.rejects(journal.update({ id: 'a', agentsStarted: 1, activeAgents: 1 }), /budget/);
  await journal.finish({ id: 'a', agentsStarted: 2, stopReason: 'error', finishedAt: 2000 });
  await assert.rejects(journal.start(record('a')), /already exists/);
});

test('recovery leaves live leases alone and marks abandoned runs interrupted', async t => {
  const { root, journal } = await fixture(t);
  await journal.start(record('active'));
  const observer = new WorkflowJournal(root, lock);
  await observer.init();
  assert.equal((await observer.list())[0].status, 'running');
  await journal.close();
  await observer.init();
  assert.equal((await observer.list())[0].status, 'interrupted');
  await observer.close();
});

test('rejects unknown fields, malformed counters, oversized records and control identities', async t => {
  const { root, journal } = await fixture(t);
  await assert.rejects(journal.start(record('bad\u0000id')), /identity/);
  await journal.start(record('a'));
  await journal.finish({ id: 'a', agentsStarted: 0, stopReason: 'completed', finishedAt: 2000 });
  const file = (await readdir(root)).find(name => name.endsWith('.json'));
  const target = join(root, file);
  const row = JSON.parse(await readFile(target, 'utf8'));
  await writeFile(target, JSON.stringify({ ...row, prompt: 'private' }));
  await assert.rejects(journal.list(), /Unknown/);
  await writeFile(target, JSON.stringify({ ...row, activeAgents: 4 }));
  await assert.rejects(journal.list(), /counters/);
  await writeFile(target, ' '.repeat(16385));
  await assert.rejects(journal.list(), /Unsafe/);
  await assert.rejects(journal.save(file.slice(0, -5), { ...row, prompt: 'private' }), /Unknown/);
});

test('rejects symlinked or writable journal ancestors', async t => {
  const { root } = await fixture(t);
  const unsafe = join(root, 'unsafe');
  await mkdir(unsafe);
  await chmod(unsafe, 0o777);
  await assert.rejects(new WorkflowJournal(join(unsafe, 'workflows'), lock).init(), /ancestor/);
  await chmod(unsafe, 0o700);
  await symlink(unsafe, join(root, 'alias'));
  await assert.rejects(new WorkflowJournal(join(root, 'alias', 'workflows'), lock).init(), /Symlinked/);
});

test('concurrent admission is serialized and journal lock symlinks fail closed', async t => {
  const { root, journal } = await fixture(t);
  const outcomes = await Promise.allSettled([journal.start(record('same')), journal.start(record('same'))]);
  assert.equal(outcomes.filter(row => row.status === 'fulfilled').length, 1);
  const target = join(root, 'target');
  const key = '0'.repeat(64);
  await symlink(target, join(root, `${key}.lock`));
  await assert.rejects(journal.lease(key), error => error.code === 'ELOOP');
});
