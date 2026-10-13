import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import * as zlib from 'node:zlib';
import { run } from './maintenance.mjs';

const base = path.resolve(process.env.DSH_RETENTION_FIXTURE_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..'));
const script = fileURLToPath(new URL('./maintenance.mjs', import.meta.url));
const env = { ...process.env };
const future = Date.parse('2030-01-01T00:00:00Z');
const old = Date.parse('2020-01-01T00:00:00Z');
const digest = data => createHash('sha256').update(data).digest('hex');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(base, '.retention-fixture-'));
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { mode: 0o700 });
  const write = (relative, data) => {
    const target = path.join(home, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
    fs.writeFileSync(target, data, { mode: 0o600 });
    return target;
  };
  write('.operations.lock', '');
  fs.mkdirSync(path.join(home, 'sessions'), { mode: 0o700 });
  t.after(() => {
    assert.equal(path.dirname(fs.realpathSync(root)), fs.realpathSync(base));
    assert.match(path.basename(root), /^\.retention-fixture-/);
    fs.rmSync(root, { recursive: true });
  });
  const session = (id, rows = [], { version = 4, compressed = false, parentSession } = {}) => {
    const header = { type: 'session', version, id, createdAt: old, isSeeded: false, delegationDepth: 0, ...(parentSession ? { parentSession } : {}) };
    const relative = `sessions/_no-cwd/${id}/session${version ? `.v${version}` : ''}.jsonl${compressed ? '.zstd' : ''}`;
    const data = `${[header, ...rows.map((row, seq) => ({ seq, time: old + seq, ...row }))].map(row => JSON.stringify(row)).join('\n')}\n`;
    const target = write(relative, compressed ? Buffer.concat(data.trimEnd().split('\n').map(line => zlib.zstdCompressSync(`${line}\n`))) : data);
    write(`sessions/_no-cwd/${id}/session.lock`, '');
    fs.utimesSync(target, old / 1000, old / 1000);
    return { relative, target, data };
  };
  const attachment = (data, { alias, fresh = false } = {}) => {
    const sha = digest(data);
    const relative = `attachments/v1/${alias ? 'file-objects' : 'objects'}/${sha.slice(0, 2)}/${sha}`;
    const target = write(relative, data);
    fs.utimesSync(target, (fresh ? future : old) / 1000, (fresh ? future : old) / 1000);
    const paths = [relative];
    if (alias) {
      const name = `attachments/v1/files/${sha.slice(0, 2)}/${sha}/${alias}`;
      fs.mkdirSync(path.dirname(path.join(home, name)), { recursive: true, mode: 0o700 });
      fs.linkSync(target, path.join(home, name));
      paths.push(name);
    }
    return { sha, target, paths };
  };
  const preview = (...args) => run(['preview', '--home', home, ...args], env);
  const apply = (plan, ...args) => run(['apply', '--home', home, '--as-of', plan.plan.parameters.asOf, '--plan-hash', plan.planHash, '--confirm', plan.confirmationToken, ...args], env);
  return { root, home, write, session, attachment, preview, apply };
}

function state(root) {
  const result = [];
  const walk = relative => {
    const target = path.join(root, relative);
    const stat = fs.lstatSync(target, { bigint: true });
    result.push([relative, String(stat.ino), String(stat.mode), String(stat.nlink), String(stat.mtimeNs), String(stat.ctimeNs), stat.isFile() ? digest(fs.readFileSync(target)) : null]);
    if (stat.isDirectory()) for (const name of fs.readdirSync(target).sort()) walk(path.join(relative, name));
  };
  walk('');
  return result;
}

function userMessage(sha) {
  return { type: 'user/message', surfaceOp: 'append', data: { role: 'user', id: 'message-1', source: { kind: 'user' }, content: [{ type: 'file', attachment: { attachmentId: `sha256:${sha}`, name: 'fixture.bin', bytes: 3 } }] } };
}

function hold(file, mode = '--shared') {
  const fd = fs.openSync(file, 'r');
  const result = spawnSync(env.DSH_RETENTION_FLOCK, [mode, '--nonblock', '3'], { stdio: ['ignore', 'pipe', 'pipe', fd] });
  assert.equal(result.status, 0, result.stderr?.toString());
  return fd;
}

test('preview requires an existing stable lock without creating data', async t => {
  const f = fixture(t);
  const lock = path.join(f.home, '.operations.lock');
  assert.equal(fs.realpathSync(lock), lock);
  fs.unlinkSync(lock);
  const before = state(f.home);
  await assert.rejects(f.preview(), /operations.lock/);
  assert.deepEqual(state(f.home), before);
});

test('default preview is read-only and exact confirmation unlinks only listed session data', async t => {
  const f = fixture(t);
  const a = f.session('selected');
  f.session('retained');
  f.write('storages/session_projcache/sessions/selected.json', JSON.stringify({ version: 7, record: { identity: { formatVersion: 4, createdAt: old }, rows: {} } }));
  const before = state(f.home);
  const empty = await run(['--home', f.home], env);
  assert.deepEqual(empty.plan.remove, []);
  const preview = await f.preview('--id', 'selected');
  assert.deepEqual(state(f.home), before);
  assert.equal(preview.plan.remove.length, 2);
  await assert.rejects(run(['apply', '--home', f.home, '--id', 'selected'], env), /as-of/);
  await assert.rejects(run(['apply', '--home', f.home, '--id', 'selected', '--as-of', preview.plan.parameters.asOf, '--plan-hash', preview.planHash, '--confirm', 'yes'], env), /confirm/);
  const bad = { ...preview, planHash: '0'.repeat(64), confirmationToken: `DELETE:${'0'.repeat(64)}` };
  await assert.rejects(f.apply(bad, '--id', 'selected'), /hash mismatch/);
  assert.deepEqual(state(f.home), before);
  const lockPaths = ['.operations.lock', 'sessions/_no-cwd/selected/session.lock', 'sessions/_no-cwd/retained/session.lock'];
  const inodes = lockPaths.map(p => fs.statSync(path.join(f.home, p)).ino);
  const result = await f.apply(preview, '--id', 'selected');
  assert.equal(result.applied, true);
  assert.equal(fs.existsSync(a.target), false);
  assert.equal(fs.existsSync(path.join(f.home, 'sessions/_no-cwd/retained/session.v4.jsonl')), true);
  assert.deepEqual(lockPaths.map(p => fs.statSync(path.join(f.home, p)).ino), inodes);
  assert.match(result.semantics, /Not secure erasure/);
});

test('retention uses latest activity, explicit timezones, and a refusal bound', async t => {
  const f = fixture(t);
  const oldSession = f.session('old');
  const recent = f.session('recent');
  fs.utimesSync(recent.target, Date.now() / 1000, Date.now() / 1000);
  const p = await f.preview('--older-than', '2021-01-01T00:00:00Z');
  assert.deepEqual(p.plan.selectedSessionIds, ['old']);
  assert.equal(p.plan.remove[0].path, oldSession.relative);
  await assert.rejects(f.preview('--older-than', '2021-01-01'), /timezone/);
  await assert.rejects(f.preview('--id', 'old', '--older-than', '2021-01-01T00:00:00Z'), /OR/);
  await assert.rejects(f.preview('--id', 'old', '--id', 'recent', '--max', '1'), /exceeds --max/);
  await assert.rejects(f.preview('--max', '1001'), /between/);
  await assert.rejects(f.preview('--id', 'missing'), /not found/);
  await assert.rejects(f.preview('--attachment-grace-days', '6'), /7–3650/);
});

test('live shared operations lock and native session locks fail before scan', async t => {
  const f = fixture(t);
  const a = f.session('selected');
  fs.writeFileSync(a.target, 'corrupt');
  const fd = hold(path.join(f.home, '.operations.lock'));
  try { await assert.rejects(f.preview('--id', 'selected'), /Live lock: .operations.lock/); }
  finally { fs.closeSync(fd); }
  const native = hold(path.join(f.home, 'sessions/_no-cwd/selected/session.lock'), '--exclusive');
  try { await assert.rejects(f.preview('--id', 'selected'), /Live lock: sessions/); }
  finally { fs.closeSync(native); }
});

test('no environment flag or fake flock executable bypasses exclusion', async t => {
  const f = fixture(t);
  f.session('selected');
  const fake = f.write('fake-flock', '#!/bin/sh\nexit 0\n');
  fs.chmodSync(fake, 0o700);
  await assert.rejects(run(['preview', '--home', f.home], { ...env, DSH_RETENTION_FLOCK: fake, DSH_OPERATIONS_LOCKED: '1' }), /flock/);
});

test('changed logs, retained records, root entries and replaced lock inode invalidate plans', async t => {
  for (const mutate of [
    f => fs.appendFileSync(path.join(f.home, 'sessions/_no-cwd/retained/session.v4.jsonl'), `${JSON.stringify({ type: 'permission/preset', seq: 0, time: old, data: { preset: 'danger-full-access' } })}\n`),
    f => f.write('storages/session_projcache/sessions/orphan.json', JSON.stringify({ version: 7, record: { identity: { createdAt: old }, rows: {} } })),
    f => f.write('unknown-backup', 'backup'),
    f => { const p = path.join(f.home, '.operations.lock'); assert.equal(fs.realpathSync(p), p); fs.renameSync(p, path.join(f.root, 'old.lock')); f.write('.operations.lock', ''); },
  ]) {
    const f = fixture(t);
    f.session('selected');
    f.session('retained');
    const preview = await f.preview('--id', 'selected');
    mutate(f);
    const before = state(f.home);
    await assert.rejects(f.apply(preview, '--id', 'selected'), /mismatch|Unrecognized/);
    assert.deepEqual(state(f.home), before);
  }
});

test('symlink roots, ancestor aliases, linked data and unsafe permissions are refused', async t => {
  const f = fixture(t);
  f.session('selected');
  const linkHome = path.join(f.root, 'alias');
  fs.symlinkSync(f.home, linkHome);
  await assert.rejects(run(['preview', '--home', linkHome], env), /symlink/);
  const data = path.join(f.home, 'sessions/_no-cwd/selected/session.v4.jsonl');
  const outside = path.join(f.root, 'outside');
  fs.linkSync(data, outside);
  await assert.rejects(f.preview(), /hardlink/);
  assert.equal(path.resolve(outside), path.join(f.root, 'outside'));
  fs.unlinkSync(outside);
  const unexpected = path.join(f.home, 'sessions/_no-cwd/selected/link');
  fs.symlinkSync(data, unexpected);
  await assert.rejects(f.preview(), /Unknown session artifact/);
  fs.chmodSync(f.home, 0o777);
  await assert.rejects(f.preview(), /permissions/);
});

test('nonsticky writable ancestors outside DSH_HOME refuse maintenance', async t => {
  const f = fixture(t);
  f.session('selected');
  fs.chmodSync(f.root, 0o777);
  const before = state(f.home);
  await assert.rejects(f.preview('--id', 'selected'), /Unsafe ancestor/);
  assert.deepEqual(state(f.home), before);
  fs.chmodSync(f.root, 0o700);
  assert.deepEqual((await f.preview('--id', 'selected')).plan.selectedSessionIds, ['selected']);
});

test('namespace root is an immutable trust anchor but must not be writable', async t => {
  const f = fixture(t);
  f.session('selected');
  const lstat = fs.lstatSync;
  let rootMode = 0o40750n;
  let foreignParent = false;
  t.mock.method(fs, 'lstatSync', (target, ...args) => {
    const stat = lstat(target, ...args);
    if (target === '/' || (foreignParent && target === f.root)) stat.uid = 65534n;
    if (target === '/') stat.mode = rootMode;
    return stat;
  });
  assert.deepEqual((await f.preview('--id', 'selected')).plan.selectedSessionIds, ['selected']);
  rootMode = 0o40777n;
  await assert.rejects(f.preview(), /Unsafe ancestor writable permissions/);
  rootMode = 0o40750n;
  foreignParent = true;
  await assert.rejects(f.preview(), /Unsafe ancestor ownership/);
});

test('malformed records, unknown versions, ignorable events and unsupported refs fail closed', async t => {
  for (const invalid of [
    data => data.slice(0, -1),
    data => `${data}{invalid}\n`,
    data => `${data}${JSON.stringify({ type: 'future/plugin', seq: 0, time: old, data: {}, ignorable: true })}\n`,
    data => `${data}${JSON.stringify({ type: 'user/message', seq: 0, time: old, data: { role: 'user' } })}\n`,
    data => `${data}${JSON.stringify({ ...userMessage('x'), seq: 0, time: old })}\n`,
    data => data.replace('"version":4', '"version":99'),
  ]) {
    const f = fixture(t);
    const a = f.session('selected');
    fs.writeFileSync(a.target, invalid(a.data));
    const before = state(f.home);
    await assert.rejects(f.preview('--id', 'selected', '--gc-attachments'), /Invalid|Incomplete|Malformed|Unsupported/);
    assert.deepEqual(state(f.home), before);
  }
});

test('older-than accounts for validated v0 and v1 packed stream timestamps', async t => {
  const f = fixture(t);
  const recent = Date.parse('2025-01-01T00:00:00Z');
  for (const version of [0, 1]) for (const completed of [false, true]) {
    const id = `legacy-${version}${completed ? '-completed' : ''}`;
    const data = [
      { type: 'session', version, id, createdAt: old, delegationDepth: 0 },
      { type: 'turn/start', seq: 0, time: old, data: { turn: 1 } },
      { type: 'step/start', seq: 1, time: old, data: { turn: 1, step: 1 } },
      { type: 'text-chunks', seq0: 2, time0: old, data: { turn: 1, step: 1, index: 0, dt: [recent - old, old - recent], texts: ['old', 'recent', 'old-clock'] } },
    ];
    if (completed) data.push({ type: 'assistant/message', seq: 5, time: old, sourceEventSeqs: [2, 3, 4], surfaceOp: 'append', data: { turn: 1, step: 1, message: { id: 'assistant-1', role: 'assistant', content: [{ type: 'text', text: 'oldrecentold-clock' }], source: { kind: 'model', provider: 'mock', model: 'mock' } } } });
    const target = f.write(`sessions/_no-cwd/${id}/session${version ? '.v1' : ''}.jsonl`, `${data.map(row => JSON.stringify(row)).join('\n')}\n`);
    f.write(`sessions/_no-cwd/${id}/session.lock`, '');
    fs.utimesSync(target, old / 1000, old / 1000);
  }
  const p = await f.preview('--older-than', '2024-01-01T00:00:00Z');
  assert.deepEqual(p.plan.selectedSessionIds, []);
  assert.deepEqual(p.plan.remove, []);
  assert.deepEqual((await f.preview('--id', 'legacy-0', '--id', 'legacy-1')).plan.selectedSessionIds, ['legacy-0', 'legacy-1']);
});

test('session cwd must identify its physical project directory', async t => {
  const f = fixture(t);
  const log = f.session('selected');
  const header = JSON.parse(log.data.trim());
  fs.writeFileSync(log.target, `${JSON.stringify({ ...header, cwd: '/fixture/project' })}\n`);
  const before = state(f.home);
  await assert.rejects(f.preview('--id', 'selected'), /project directory/);
  assert.deepEqual(state(f.home), before);
  const projectDirectory = path.join(f.home, 'sessions/--fixture-project--');
  fs.mkdirSync(projectDirectory, { mode: 0o700 });
  const source = path.dirname(log.target);
  const target = path.join(projectDirectory, 'selected');
  assert.equal(fs.realpathSync(source), path.join(f.home, 'sessions/_no-cwd/selected'));
  assert.equal(target, path.join(f.home, 'sessions/--fixture-project--/selected'));
  fs.renameSync(source, target);
  assert.deepEqual((await f.preview('--id', 'selected')).plan.selectedSessionIds, ['selected']);
  fs.writeFileSync(path.join(target, 'session.v4.jsonl'), log.data);
  await assert.rejects(f.preview('--id', 'selected'), /project directory/);
});

test('zstd, all canonical generations and hidden historical references are scanned', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const historical = f.attachment(Buffer.from('historical'));
  f.session('selected', [], { compressed: true });
  f.session('retained', [userMessage(historical.sha)], { version: 3, compressed: true });
  f.session('retained', []);
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  assert.equal(p.plan.remove.length, 1);
  assert.match(p.plan.remove[0].path, /zstd$/);
  await f.apply(p, '--id', 'selected', '--gc-attachments');
  assert.equal(fs.existsSync(historical.target), true);
  const broken = f.session('broken', [], { compressed: true });
  fs.appendFileSync(broken.target, Buffer.from('bad-frame'));
  await assert.rejects(f.preview('--gc-attachments'), /Zstandard/);
});

test('GC protects retained logs, storage refs, orphan projections and fresh pending saves', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const shared = f.attachment(Buffer.from('shared'));
  const storage = f.attachment(Buffer.from('storage'));
  const fresh = f.attachment(Buffer.from('pending-save'), { fresh: true });
  const garbage = f.attachment(Buffer.from('garbage'), { alias: 'fixture.bin' });
  f.session('selected', [userMessage(shared.sha)]);
  f.session('retained', [userMessage(shared.sha)]);
  f.write('storages/session_projcache/sessions/orphan.json', JSON.stringify({ version: 7, record: { identity: { createdAt: old }, rows: { upload: { ver: 1, seq: -1, val: { attachmentId: `sha256:${storage.sha}` } } } } }));
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  assert.deepEqual(p.plan.leftovers.orphanProjectionIds, ['orphan']);
  assert.deepEqual(p.plan.remove.filter(item => item.kind === 'attachment').map(item => item.path).sort(), garbage.paths.sort());
  await f.apply(p, '--id', 'selected', '--gc-attachments');
  for (const a of [shared, storage, fresh]) assert.equal(fs.existsSync(a.target), true);
  for (const relative of garbage.paths) assert.equal(fs.existsSync(path.join(f.home, relative)), false);
});

test('attachment unlink waits for durable deletion of every log and projection reference', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const garbage = f.attachment(Buffer.from('gc-ordering'));
  f.session('selected', [userMessage(garbage.sha)]);
  f.write('storages/session_projcache/sessions/selected.json', JSON.stringify({ version: 7, record: { identity: { formatVersion: 4, createdAt: old }, rows: {} } }));
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  const events = [];
  const unlink = fs.unlinkSync;
  const sync = fs.fsyncSync;
  t.mock.method(fs, 'unlinkSync', target => {
    events.push(['unlink', path.relative(f.home, target)]);
    return unlink(target);
  });
  t.mock.method(fs, 'fsyncSync', fd => {
    events.push(['sync', path.relative(f.home, fs.readlinkSync(`/proc/self/fd/${fd}`))]);
    return sync(fd);
  });
  await f.apply(p, '--id', 'selected', '--gc-attachments');
  const firstAttachment = events.findIndex(([kind, target]) => kind === 'unlink' && target.startsWith('attachments/'));
  assert.ok(firstAttachment >= 0);
  for (const item of p.plan.remove.filter(item => item.kind !== 'attachment')) {
    const unlinkIndex = events.findIndex(([kind, target]) => kind === 'unlink' && target === item.path);
    const syncIndex = events.findIndex(([kind, target]) => kind === 'sync' && target === path.dirname(item.path));
    assert.ok(unlinkIndex >= 0 && unlinkIndex < syncIndex && syncIndex < firstAttachment);
  }
});

test('reference directory sync failure keeps every attachment and attempts partial-delete sync', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const garbage = f.attachment(Buffer.from('gc-sync-failure'), { alias: 'fixture.bin' });
  const selected = f.session('selected', [userMessage(garbage.sha)]);
  f.write('storages/session_projcache/sessions/selected.json', JSON.stringify({ version: 7, record: { identity: { formatVersion: 4, createdAt: old }, rows: {} } }));
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  const before = state(path.join(f.home, 'attachments'));
  const attempted = [];
  const sync = fs.fsyncSync;
  t.mock.method(fs, 'fsyncSync', fd => {
    const relative = path.relative(f.home, fs.readlinkSync(`/proc/self/fd/${fd}`));
    attempted.push(relative);
    if (relative === path.dirname(selected.relative)) throw new Error('fixture fsync failure');
    return sync(fd);
  });
  await assert.rejects(f.apply(p, '--id', 'selected', '--gc-attachments'), /synchronization failed.*partial apply.*not be durable/);
  assert.deepEqual(state(path.join(f.home, 'attachments')), before);
  assert.equal(fs.existsSync(selected.target), false);
  assert.ok(attempted.includes('storages/session_projcache/sessions'));
  assert.ok(attempted.filter(relative => relative === path.dirname(selected.relative)).length >= 2);
});

test('new ctime protects deduplicated old attachments for at least seven days', async t => {
  const f = fixture(t);
  const oldMtime = f.attachment(Buffer.from('recently-published-old-mtime'));
  const p = await f.preview('--gc-attachments');
  assert.deepEqual(p.plan.remove, []);
  assert.equal(p.plan.protectedAttachmentDigests, 1);
  assert.equal(fs.existsSync(oldMtime.target), true);
});

test('GC refuses backups, unknown stores, pending temp uploads, corrupt blobs and external hardlinks', async t => {
  for (const mutate of [
    f => f.write('sessions/_no-cwd/selected/session.v4.jsonl.bak', 'backup'),
    f => f.write('storages/unknown.json', '{}'),
    f => f.write('storages/session_projcache/sessions/selected.json.bak.123', '{}'),
    f => f.write('attachments/v1/tmp/pending', 'pending'),
    f => f.write('cache/unknown-store.sqlite', 'sqlite'),
    f => { const a = f.attachment(Buffer.from('corrupt')); fs.writeFileSync(a.target, 'changed'); },
    f => { const a = f.attachment(Buffer.from('outside-link')); fs.linkSync(a.target, path.join(f.root, 'outside-attachment')); },
  ]) {
    const f = fixture(t);
    f.session('selected');
    mutate(f);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /Unknown|Unrecognized|unscanned|Pending|Corrupt|hardlinks/);
    assert.deepEqual(state(f.home), before);
  }
});

test('workspace selection metadata is atomically pruned without changing user fields, legacy rehydration is refused', async t => {
  const f = fixture(t);
  f.session('selected');
  const workspace = { unit: { name: 'workspace', version: 2 }, global: { initialized: true, workspaceIds: ['work'], pinnedSessionIds: ['selected'] }, tables: { workspaces: { work: { path: '/fixture', title: 'Fixture', createdAt: '2020-01-01', updatedAt: '2020-01-01', sessionIds: ['selected'] } } } };
  f.write('storages/workspace.json', JSON.stringify(workspace));
  const p = await f.preview('--id', 'selected');
  assert.deepEqual(p.plan.leftovers.workspaceSessionIds, []);
  assert.deepEqual(p.plan.workspaceUpdate.removeSessionIds, ['selected']);
  await f.apply(p, '--id', 'selected');
  workspace.global.pinnedSessionIds = [];
  workspace.tables.workspaces.work.sessionIds = [];
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.home, 'storages/workspace.json'), 'utf8')), workspace);
  assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), false);
  f.session('selected');
  f.write('storages/session_projcache.json', JSON.stringify({ unit: { name: 'session_projcache', version: 7 }, tables: { sessions: { selected: { identity: { createdAt: old }, rows: {} } } }, global: null }));
  await assert.rejects(f.preview('--id', 'selected'), /legacy projection storage/);
});

test('operations and plugin stores are preserved and block attachment GC', async t => {
  for (const directory of ['operations', 'plugins']) {
    const f = fixture(t);
    f.session('selected');
    f.write(`${directory}/opaque-store`, 'preserved auxiliary state');
    const before = state(path.join(f.home, directory));
    const p = await f.preview('--id', 'selected');
    assert.deepEqual(p.plan.leftovers.auxiliary, [directory]);
    await assert.rejects(f.preview('--id', 'selected', '--gc-attachments'), /unscanned auxiliary stores/);
    await f.apply(p, '--id', 'selected');
    assert.deepEqual(state(path.join(f.home, directory)), before);
  }
});

test('apply rescan detects modifications after its first scan before any unlink', async t => {
  const f = fixture(t);
  f.session('selected');
  f.session('retained');
  const p = await f.preview('--id', 'selected');
  const readdir = fs.readdirSync;
  let rootReads = 0;
  t.mock.method(fs, 'readdirSync', (target, ...args) => {
    if (target === f.home && ++rootReads === 2) f.write('storages/unknown.json', '{}');
    return readdir(target, ...args);
  });
  await assert.rejects(f.apply(p, '--id', 'selected'), /Unrecognized|changed during scan/);
  assert.equal(fs.existsSync(path.join(f.home, 'sessions/_no-cwd/selected/session.v4.jsonl')), true);
});

test('deletion verification has its own bounded read budget after the final scan', async t => {
  const f = fixture(t);
  const ids = ['a', 'b', 'c'];
  ids.forEach(id => f.session(id));
  const read = fs.readFileSync;
  const readlink = fs.readlinkSync;
  t.mock.method(fs, 'readFileSync', (target, ...args) => {
    const data = read(target, ...args);
    if (typeof target === 'number' && readlink(`/proc/self/fd/${target}`).endsWith('/session.v4.jsonl')) {
      Object.defineProperty(data, 'length', { value: 256 * 1024 * 1024 });
    }
    return data;
  });
  const selectors = ids.flatMap(id => ['--id', id]);
  const p = await f.preview(...selectors);
  const result = await f.apply(p, ...selectors);
  assert.equal(result.applied, true);
  assert.equal(result.removed.length, ids.length);
});

test('direct CLI entry enforces lock and returns machine-readable plan', t => {
  const f = fixture(t);
  f.session('selected');
  const preview = spawnSync(process.execPath, [script, 'preview', '--home', f.home, '--id', 'selected'], { env, encoding: 'utf8' });
  assert.equal(preview.status, 0, preview.stderr);
  assert.deepEqual(JSON.parse(preview.stdout).plan.selectedSessionIds, ['selected']);
  const fd = hold(path.join(f.home, '.operations.lock'));
  try {
    const result = spawnSync(process.execPath, [script, 'preview', '--home', f.home], { env: { ...env, DSH_OPERATIONS_LOCKED: '1' }, encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Live lock/);
  } finally { fs.closeSync(fd); }
});


function workspaceFixture(f, sessionIds = ['selected', 'retained']) {
  const doc = { unit: { name: 'workspace', version: 2 }, global: { initialized: true, defaultWorkspaceId: 'work', workspaceIds: ['work'], archivedSessionIds: ['selected'], pinnedSessionIds: ['retained'] }, tables: { workspaces: { work: { path: '/fixture/user-project', title: 'User title', createdAt: '2020-01-01', updatedAt: '2021-01-01', sessionIds } } } };
  const bytes = JSON.stringify(doc);
  f.write('storages/workspace.json', bytes);
  return { doc, bytes };
}

test('calendar timestamps reject normalized dates, invalid offsets and midnight overflow', async t => {
  const f = fixture(t);
  for (const date of ['2025-02-29T00:00:00Z', '2024-02-30T01:00:00+09:00', '2025-04-31T00:00:00Z', '2025-01-01T24:00:00Z', '2025-01-01T00:00:00+24:00', '2025-01-01T00:00:00+00:60']) await assert.rejects(f.preview('--older-than', date), /Invalid calendar/);
  assert.deepEqual((await f.preview('--older-than', '2024-02-29T12:30:01.2+09:00')).plan.remove, []);
});

test('configured profiles, plugin settings, journal, raw logs and caches retain every referenced digest', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  f.session('selected');
  const attachments = Array.from({ length: 7 }, (_, index) => f.attachment(Buffer.from(`auxiliary-${index}`)));
  const garbage = f.attachment(Buffer.from('auxiliary-garbage'));
  f.write('profiles/nix-web/package.json', JSON.stringify({ name: 'dsh-profile-nix-web', private: true, dependencies: {}, dsh: { profile: { bundles: [] } } }));
  f.write('profiles/nix-web/cordis.patch.yml', `- id: ordinary-plugin\n  config:\n    image: ${attachments[0].sha}\n- id: session-persistence-jsonl\n  config:\n    root: !!js dshHomePath('sessions')\n`);
  f.write('profiles/nix-web/pnpm-workspace.yaml', 'packages: []\n');
  f.write('profiles/nix-web/.nix-managed', 'owner=nix\nschema=1\nprofile=nix-web\n');
  f.write('profiles/.nix-sync.lock', '');
  f.write('plugins/subscriptions/provider-settings.json', JSON.stringify({ providers: {}, toolHistory: [{ attachmentId: `sha256:${attachments[1].sha}` }] }));
  f.write(`operations/workflows/${'a'.repeat(64)}.json`, JSON.stringify({ version: 1, id: 'fixture', parentSessionId: 'selected', name: attachments[2].sha, status: 'completed' }));
  f.write(`operations/workflows/${'a'.repeat(64)}.lock`, '');
  f.write('logs/runtime.log', `retained image ${attachments[3].sha}\n`);
  f.write('cache/model-index.json', JSON.stringify({ escapedDigest: attachments[4].sha }).replace(attachments[4].sha[0], `\\u00${attachments[4].sha.charCodeAt(0).toString(16)}`));
  f.write('settings.yaml', `ordinary:\n  image: ${attachments[5].sha}\n`);
  f.write(`cache/attachments/request-images/aa/${'a'.repeat(64)}`, Buffer.concat([Buffer.from([255, 216, 255]), Buffer.from(attachments[6].sha)]));
  const preserved = ['profiles', 'plugins', 'operations', 'logs', 'cache'].map(relative => [relative, state(path.join(f.home, relative))]);
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  assert.deepEqual(p.plan.remove.filter(item => item.kind === 'attachment').map(item => item.path), garbage.paths);
  assert.deepEqual(p.plan.auxiliaryScan.unscanned, []);
  assert.ok(p.plan.auxiliaryScan.scanned.some(item => item.path === 'plugins/subscriptions/provider-settings.json'));
  await f.apply(p, '--id', 'selected', '--gc-attachments');
  for (const item of attachments) assert.equal(fs.existsSync(item.target), true);
  assert.equal(fs.existsSync(garbage.target), false);
  for (const [relative, before] of preserved) assert.deepEqual(state(path.join(f.home, relative)), before);
});

test('known Nix package links are excluded only at exact immutable code roots', async t => {
  const f = fixture(t);
  f.session('selected');
  const catalogPackage = path.resolve(path.dirname(env.DSH_RETENTION_CATALOG), '..');
  fs.mkdirSync(path.join(f.home, 'profiles/nix-web/node_modules/@deepseek-ai'), { recursive: true, mode: 0o700 });
  const link = path.join(f.home, 'profiles/nix-web/node_modules/@deepseek-ai/dsh-session-format-catalog');
  fs.symlinkSync(catalogPackage, link);
  const before = state(f.home);
  const p = await f.preview('--gc-attachments');
  assert.equal(p.plan.auxiliaryScan.immutableCode.length, 1);
  assert.deepEqual(state(f.home), before);
  assert.equal(fs.realpathSync(link), catalogPackage);
  fs.unlinkSync(link);
  fs.symlinkSync(path.dirname(catalogPackage), link);
  await assert.rejects(f.preview('--gc-attachments'), /code-root semantics/);
});

test('external state, Nix-linked state, profile links and unknown binary stores refuse GC', async t => {
  for (const mutate of [
    f => { f.write('plugins/subscriptions/placeholder.json', '{}'); fs.symlinkSync(f.root, path.join(f.home, 'plugins/subscriptions/external')); },
    f => { f.write('plugins/subscriptions/placeholder.json', '{}'); fs.symlinkSync(env.DSH_RETENTION_CATALOG, path.join(f.home, 'plugins/subscriptions/state.json')); },
    f => { fs.mkdirSync(path.join(f.home, 'profiles')); fs.symlinkSync(f.root, path.join(f.home, 'profiles/web')); },
    f => f.write('plugins/subscriptions/settings.json', Buffer.from([255, 254, 1])),
    f => f.write('plugins/custom/unknown.sqlite', 'opaque'),
    f => f.write('cache/request-image.bin', 'opaque'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: storage-domain\n  config:\n    backend: remote\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: storage-json\n  config:\n    root: /external/state\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: session-persistence-jsonl\n  name: custom-backend\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: attachment-local\n  config:\n    dshHome: /external/attachments\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: remote-storage\n  name: custom-storage\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: session-query-sqlite\n  config:\n    path: /external/index.sqlite\n    openAt: startup\n'),
    f => f.write('profiles/web/cordis.patch.yml', '- id: storage-json\n  config: !!js computeRoot()\n'),
  ]) {
    const f = fixture(t);
    f.session('selected');
    mutate(f);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /symlink|Malformed|Unrecognized|backend|Backend|query|Dynamic|Unknown plugin/);
    assert.deepEqual(state(f.home), before);
  }
});

test('auxiliary changes invalidate confirmation and nesting, byte and alias bounds refuse', async t => {
  const f = fixture(t);
  f.session('selected');
  const settings = f.write('plugins/subscriptions/provider-settings.json', '{}');
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  fs.writeFileSync(settings, '{"changed":true}');
  await assert.rejects(f.apply(p, '--id', 'selected', '--gc-attachments'), /hash mismatch/);
  fs.writeFileSync(settings, '['.repeat(101) + '0' + ']'.repeat(101));
  await assert.rejects(f.preview('--gc-attachments'), /nesting/);
  fs.writeFileSync(settings, '{}');
  f.write('profiles/web/cordis.patch.yml', 'cycle: &cycle\n  next: *cycle\n');
  await assert.rejects(f.preview('--gc-attachments'), /alias cycle/);
});

test('workspace pruning is durable before logs and changes only selected-ID arrays', async t => {
  const f = fixture(t);
  f.session('selected'); f.session('retained');
  const { doc } = workspaceFixture(f);
  const p = await f.preview('--id', 'selected');
  const sync = fs.fsyncSync;
  const unlink = fs.unlinkSync;
  const events = [];
  t.mock.method(fs, 'fsyncSync', fd => { events.push(['sync', path.relative(f.home, fs.readlinkSync(`/proc/self/fd/${fd}`))]); return sync(fd); });
  t.mock.method(fs, 'unlinkSync', target => {
    if (target.endsWith('session.v4.jsonl')) {
      assert.ok(events.some(([kind, relative]) => kind === 'sync' && relative === 'storages'));
      const changed = JSON.parse(fs.readFileSync(path.join(f.home, 'storages/workspace.json')));
      assert.deepEqual(changed.tables.workspaces.work.sessionIds, ['retained']);
      assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), true);
    }
    events.push(['unlink', path.relative(f.home, target)]);
    return unlink(target);
  });
  await f.apply(p, '--id', 'selected');
  doc.global.archivedSessionIds = [];
  doc.tables.workspaces.work.sessionIds = ['retained'];
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.home, 'storages/workspace.json'))), doc);
});

test('workspace replacement failure rolls back before any log deletion', async t => {
  for (const stage of ['rename', 'directory-sync', 'log-unlink']) {
    const f = fixture(t);
    const selected = f.session('selected');
    f.session('retained');
    const { bytes } = workspaceFixture(f);
    const p = await f.preview('--id', 'selected');
    let injected = false;
    const method = stage === 'rename' ? 'renameSync' : stage === 'directory-sync' ? 'fsyncSync' : 'unlinkSync';
    const original = fs[method];
    const mock = t.mock.method(fs, method, (...args) => {
      const target = stage === 'directory-sync' ? fs.readlinkSync(`/proc/self/fd/${args[0]}`) : args[0];
      if (!injected && (stage === 'rename' ? target.endsWith('.retention-workspace.tmp') : stage === 'directory-sync' ? target.endsWith('/storages') && fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')) : target === selected.target)) {
        injected = true;
        throw new Error(`fixture ${stage} failure`);
      }
      return original(...args);
    });
    await assert.rejects(f.apply(p, '--id', 'selected'), /workspace selection metadata rolled back/);
    mock.mock.restore();
    assert.equal(fs.readFileSync(path.join(f.home, 'storages/workspace.json'), 'utf8'), bytes);
    assert.equal(fs.existsSync(selected.target), true);
    assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), false);
  }
});

test('partial log deletion preserves workspace journal and explicit recovery keeps IDs pruned', async t => {
  const f = fixture(t);
  f.session('selected'); f.session('selected', [], { version: 3 }); f.session('retained');
  workspaceFixture(f);
  const p = await f.preview('--id', 'selected');
  const unlink = fs.unlinkSync;
  let logs = 0;
  const mock = t.mock.method(fs, 'unlinkSync', target => {
    if (target.includes('/sessions/') && ++logs === 2) throw new Error('fixture second log failure');
    return unlink(target);
  });
  await assert.rejects(f.apply(p, '--id', 'selected'), /journal retained.*partial apply/);
  mock.mock.restore();
  const before = state(f.home);
  await assert.rejects(f.preview(), /recover-workspace/);
  assert.deepEqual(state(f.home), before);
  const result = await run(['recover-workspace', '--home', f.home, '--confirm', 'RECOVER-WORKSPACE'], env);
  assert.equal(result.workspace, 'kept-pruned-after-log-deletion');
  const changed = JSON.parse(fs.readFileSync(path.join(f.home, 'storages/workspace.json')));
  assert.deepEqual(changed.tables.workspaces.work.sessionIds, ['retained']);
  assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), false);
  await f.preview();
});

test('unknown workspace fields, pending mutation and inconsistent ownership refuse before writes', async t => {
  for (const mutate of [
    doc => { doc.global.future = true; },
    doc => { doc.tables.workspaces.work.extra = 'untouched user data'; },
    doc => { doc.global.pendingMutation = { operation: 'delete', workspaceId: 'work' }; },
    doc => { doc.global.workspaceIds = []; },
    doc => { doc.tables.workspaces.work.sessionIds.push('selected'); },
    doc => { doc.global.pinnedSessionIds = ['selected']; },
  ]) {
    const f = fixture(t);
    f.session('selected');
    const { doc } = workspaceFixture(f);
    mutate(doc);
    f.write('storages/workspace.json', JSON.stringify(doc));
    const before = state(f.home);
    await assert.rejects(f.preview('--id', 'selected'), /Unknown|unfinished|disagree|conflict/);
    assert.deepEqual(state(f.home), before);
  }
});

test('migration recovery gate blocks maintenance, retained JSON migration backups protect digests', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const preserved = f.attachment(Buffer.from('migration-source-reference'));
  const key = 'b'.repeat(64);
  f.write(`operations/migrations/${key}/source.bin`, JSON.stringify({ attachmentId: `sha256:${preserved.sha}` }));
  f.write(`operations/migrations/${key}/manifest.json`, '{"version":1}');
  assert.deepEqual((await f.preview('--gc-attachments')).plan.remove, []);
  f.write('operations/migrations/active.json', '{"status":"completed"}');
  const before = state(f.home);
  await assert.rejects(f.preview(), /Unfinished storage migration/);
  assert.deepEqual(state(f.home), before);
});

test('CLI help disclaims external, backup and remote-provider erasure', async () => {
  const result = await run(['--help'], {});
  assert.match(result.help, /exports, backups.*remote-provider copies are never erased/);
  assert.match(result.help, /recover-workspace/);
});


test('materialized Nix profile scans actual immutable bundle patches without executing expressions', async t => {
  const f = fixture(t);
  const modules = env.DSH_RETENTION_NODE_MODULES;
  assert.ok(modules, 'DSH_RETENTION_NODE_MODULES must point to the immutable composed fixture code anchor');
  f.session('selected');
  f.write('profiles/nix-web/package.json', JSON.stringify({ name: 'dsh-profile-nix-web', private: true, dependencies: {}, dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'] } } }));
  f.write('profiles/nix-web/cordis.patch.yml', '- id: operations\n  config:\n    persistence: launch-reset\n');
  const before = state(f.home);
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  assert.ok(p.plan.auxiliaryScan.scanned.some(item => item.path.endsWith('/dsh-base/cordis.patch.yml')));
  assert.deepEqual(state(f.home), before);
  await f.apply(p, '--id', 'selected', '--gc-attachments');
});

const sqliteSchemas = {
  privacy: `CREATE TABLE privacy_choices (channel TEXT PRIMARY KEY, enabled INTEGER NOT NULL CHECK(enabled IN (0,1)), revision INTEGER NOT NULL CHECK(revision>=0), updated_at INTEGER NOT NULL) STRICT;`,
  checkpoints: `CREATE TABLE checkpoint_runs (id TEXT PRIMARY KEY, root_id TEXT NOT NULL, root_identity TEXT NOT NULL, status TEXT NOT NULL, revision INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deadline_at INTEGER, graph_json TEXT NOT NULL, backend TEXT NOT NULL, cwd TEXT NOT NULL, max_attempts INTEGER NOT NULL, attempts_started INTEGER NOT NULL DEFAULT 0, owner_token TEXT);
    CREATE TABLE checkpoint_nodes (run_id TEXT NOT NULL REFERENCES checkpoint_runs(id), id TEXT NOT NULL, status TEXT NOT NULL, attempt INTEGER NOT NULL, PRIMARY KEY(run_id,id));
    CREATE TABLE checkpoint_attempts (run_id TEXT NOT NULL, node_id TEXT NOT NULL, attempt INTEGER NOT NULL, status TEXT NOT NULL, child_id TEXT, result_json TEXT, error TEXT, started_at INTEGER, finished_at INTEGER, PRIMARY KEY(run_id,node_id,attempt), FOREIGN KEY(run_id,node_id) REFERENCES checkpoint_nodes(run_id,id));
    CREATE TABLE checkpoint_actions (id TEXT PRIMARY KEY, run_id TEXT REFERENCES checkpoint_runs(id), root_id TEXT, action TEXT, prior_revision INTEGER, at INTEGER, actor TEXT);
    CREATE INDEX checkpoint_owner ON checkpoint_runs(root_id,updated_at);`,
  budget: `CREATE TABLE budget_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE budget_owners (id TEXT PRIMARY KEY, pid INTEGER NOT NULL, start TEXT NOT NULL, closed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE budget_roots (id TEXT PRIMARY KEY, limits_json TEXT NOT NULL, revision INTEGER NOT NULL);
    CREATE TABLE budget_sessions (id TEXT PRIMARY KEY, created_at INTEGER, parent_id TEXT, root_id TEXT NOT NULL REFERENCES budget_roots(id));
    CREATE TABLE budget_requests (id TEXT PRIMARY KEY, root_id TEXT NOT NULL REFERENCES budget_roots(id), session_id TEXT NOT NULL REFERENCES budget_sessions(id), owner_id TEXT NOT NULL REFERENCES budget_owners(id), provider TEXT NOT NULL, model TEXT NOT NULL, purpose TEXT NOT NULL, state TEXT NOT NULL, output_reserved INTEGER NOT NULL, input_upper INTEGER, cost_reserved INTEGER NOT NULL, pricing_json TEXT, usage_json TEXT, cost_micros INTEGER, settlement_json TEXT);
    CREATE INDEX budget_requests_root ON budget_requests(root_id);
    CREATE TABLE budget_children (id TEXT PRIMARY KEY, root_id TEXT NOT NULL REFERENCES budget_roots(id), parent_id TEXT NOT NULL REFERENCES budget_sessions(id), child_id TEXT NOT NULL, owner_id TEXT NOT NULL REFERENCES budget_owners(id), kind TEXT NOT NULL, provider TEXT NOT NULL, state TEXT NOT NULL);
    CREATE INDEX budget_children_root ON budget_children(root_id);`,
};

async function sqliteFixture(f, name, mutate = () => {}) {
  const { DatabaseSync } = await import('node:sqlite');
  const target = f.write(`operations/${name}.sqlite`, '');
  const db = new DatabaseSync(target);
  try {
    db.exec(`PRAGMA journal_mode=WAL; ${sqliteSchemas[name]} PRAGMA user_version=1;`);
    mutate(db);
  } finally { db.close(); }
  return target;
}

test('known closed operations SQLite schemas retain JSON and raw digest references without writes', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const retained = f.attachment(Buffer.from('checkpoint-reference'));
  const budget = f.attachment(Buffer.from('budget-metadata-digest'));
  const garbage = f.attachment(Buffer.from('sqlite-garbage'));
  await sqliteFixture(f, 'privacy', db => db.exec("INSERT INTO privacy_choices VALUES ('product-analytics',0,0,0)"));
  await sqliteFixture(f, 'budget', db => db.prepare('INSERT INTO budget_meta VALUES (?,?)').run('format', budget.sha));
  const escaped = JSON.stringify({ attachmentId: `sha256:${retained.sha}` }).replace(retained.sha, [...retained.sha].map(char => `\\u00${char.charCodeAt(0).toString(16)}`).join(''));
  await sqliteFixture(f, 'checkpoints', db => db.prepare('INSERT INTO checkpoint_runs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run('fixture', 'root', 'identity', 'paused', 1, 0, 0, null, escaped, 'local', '/fixture', 1, 0, null));
  f.write(`operations/checkpoints-locks/${'a'.repeat(64)}.lock`, '');
  const before = state(path.join(f.home, 'operations'));
  const p = await f.preview('--gc-attachments');
  assert.deepEqual(p.plan.remove.map(item => item.path), garbage.paths);
  await f.apply(p, '--gc-attachments');
  assert.deepEqual(state(path.join(f.home, 'operations')), before);
  assert.equal(fs.existsSync(retained.target), true);
  assert.equal(fs.existsSync(budget.target), true);
});

test('operations SQLite unknown schemas, binary cells, versions and sidecars fail closed', async t => {
  for (const mutation of [
    db => db.exec('CREATE TABLE future(value TEXT)'),
    db => db.exec('ALTER TABLE privacy_choices ADD COLUMN future TEXT'),
    db => db.exec('PRAGMA user_version=2'),
    db => db.exec('CREATE VIEW future AS SELECT * FROM privacy_choices'),
  ]) {
    const f = fixture(t);
    await sqliteFixture(f, 'privacy', mutation);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /Unknown operations database/);
    assert.deepEqual(state(f.home), before);
  }
  for (const suffix of ['-wal', '-shm', '-journal']) {
    const f = fixture(t);
    await sqliteFixture(f, 'privacy');
    f.write(`operations/privacy.sqlite${suffix}`, 'pending');
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /sidecar requires/);
    assert.deepEqual(state(f.home), before);
  }
  const f = fixture(t);
  await sqliteFixture(f, 'budget', db => db.exec("INSERT INTO budget_meta VALUES ('binary',X'0001')"));
  await assert.rejects(f.preview('--gc-attachments'), /value encoding/);
});


test('hex-adjacent and escaped raw digest references are conservatively protected', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const embedded = f.attachment(Buffer.from('hex-adjacent'));
  const escaped = f.attachment(Buffer.from('escaped-raw'));
  f.write('logs/retained.log', `a${embedded.sha}f\n${[...escaped.sha].map(char => `\\u00${char.charCodeAt(0).toString(16)}`).join('')}\n`);
  assert.deepEqual((await f.preview('--gc-attachments')).plan.remove, []);
});

test('replacement directory sync failure retains durable rollback journal until explicit recovery', async t => {
  const f = fixture(t);
  const selected = f.session('selected'); f.session('retained');
  const { bytes } = workspaceFixture(f);
  const p = await f.preview('--id', 'selected');
  const sync = fs.fsyncSync;
  let directorySyncs = 0;
  const mock = t.mock.method(fs, 'fsyncSync', fd => {
    const target = fs.readlinkSync(`/proc/self/fd/${fd}`);
    if (target === path.join(f.home, 'storages') && ++directorySyncs >= 2) throw new Error('fixture persistent directory sync failure');
    return sync(fd);
  });
  await assert.rejects(f.apply(p, '--id', 'selected'), /workspace recovery required/);
  mock.mock.restore();
  assert.equal(fs.existsSync(selected.target), true);
  assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), true);
  const before = state(f.home);
  await assert.rejects(f.apply(p, '--id', 'selected'), /recover-workspace/);
  assert.deepEqual(state(f.home), before);
  const lock = hold(path.join(f.home, 'sessions/_no-cwd/selected/session.lock'), '--exclusive');
  try { await assert.rejects(run(['recover-workspace', '--home', f.home, '--confirm', 'RECOVER-WORKSPACE'], env), /Live lock/); }
  finally { fs.closeSync(lock); }
  const result = await run(['recover-workspace', '--home', f.home, '--confirm', 'RECOVER-WORKSPACE'], env);
  assert.equal(result.workspace, 'rolled-back-before-log-deletion');
  assert.equal(fs.readFileSync(path.join(f.home, 'storages/workspace.json'), 'utf8'), bytes);
});


test('dynamic group, preset and include composition refuses GC without evaluating JavaScript', async t => {
  const expression = `!!js "[{ id: 'storage-json', config: { root: '/external/state' } }]"`;
  for (const document of [
    `- insert:\n    - id: hidden\n      name: cordis:group\n      config: ${expression}\n`,
    `- insert:\n    - id: hidden\n      name: '@deepseek-ai/cordis-plugin-group'\n      group: true\n      config: ${expression}\n`,
    `- id: planning\n  config: ${expression}\n`,
    `- insert:\n    - id: preset\n      name: '@deepseek-ai/dsh-agent-preset'\n      config:\n        id: fixture\n        plugins: ${expression}\n`,
    `- id: preset-standard\n  config:\n    plugins:\n      - ${expression}\n`,
    `- insert: ${expression}\n`,
    `- imports: ${expression}\n`,
    `- include: ${expression}\n`,
  ]) {
    const f = fixture(t);
    f.write('profiles/web/cordis.patch.yml', document);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /Dynamic.*(?:composition|configuration)/);
    assert.deepEqual(state(f.home), before);
  }
});


test('disabled unsafe backend configuration remains refused when later patches can reenable it', async t => {
  for (const first of [
    '- id: storage-json\n  disabled: true\n  config:\n    root: /external/state\n',
    '- id: storage-json\n  disabled: true\n  name: custom-backend\n',
    '- id: attachment-local\n  disabled: true\n  config:\n    dshHome: /external/attachments\n',
  ]) {
    const f = fixture(t);
    f.write('profiles/web/cordis.patch.yml', `${first}- id: storage-json\n  disabled: false\n- id: attachment-local\n  disabled: false\n`);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /backend/);
    assert.deepEqual(state(f.home), before);
  }
});


test('patched schedule v1 tasks and outbox retain references and bytes while unknown fields refuse', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  f.session('selected');
  const task = f.attachment(Buffer.from('schedule-task'));
  const pending = f.attachment(Buffer.from('schedule-outbox'));
  const garbage = f.attachment(Buffer.from('schedule-garbage'));
  const document = { unit: { name: 'schedule', version: 1 }, global: null, tables: {
    tasks: { reminder: { sessionId: 'selected', record: { id: 'reminder', prompt: task.sha, scheduledAt: '2020-01-01T00:00:00.000Z' }, status: 'active' } },
    outbox: { message: { id: 'message', sessionId: 'selected', text: pending.sha, members: [{ taskId: 'reminder', prompt: pending.sha, scheduledAt: '2020-01-01T00:00:00.000Z', nextScheduledAt: '2030-01-01T00:00:00.000Z', targetAt: '2020-01-01T00:00:00.000Z' }], attempts: 1, retryAt: 0 } },
  } };
  const original = JSON.stringify(document);
  const target = f.write('storages/schedule.json', original);
  const p = await f.preview('--id', 'selected', '--gc-attachments');
  assert.deepEqual(p.plan.remove.filter(item => item.kind === 'attachment').map(item => item.path), garbage.paths);
  await f.apply(p, '--id', 'selected', '--gc-attachments');
  assert.equal(fs.readFileSync(target, 'utf8'), original);
  assert.equal(fs.existsSync(task.target), true);
  assert.equal(fs.existsSync(pending.target), true);
  for (const counters of [{ recoveryCount: 0, totalAttempts: 1 }, { recoveryCount: 100, totalAttempts: 501 }]) {
    const updated = structuredClone(document);
    Object.assign(updated.tables.outbox.message, counters);
    const serialized = JSON.stringify(updated);
    fs.writeFileSync(target, serialized);
    await f.preview('--gc-attachments');
    assert.equal(fs.readFileSync(target, 'utf8'), serialized);
  }
  for (const mutation of [
    doc => { doc.tables.future = {}; },
    doc => { doc.tables.outbox.message.future = true; },
    doc => { doc.tables.outbox.message.attempts = 6; },
    doc => { doc.tables.outbox.message.recoveryCount = 1; },
    doc => { Object.assign(doc.tables.outbox.message, { recoveryCount: 1, totalAttempts: 1 }); },
    doc => { Object.assign(doc.tables.outbox.message, { recoveryCount: 101, totalAttempts: 506 }); },
    doc => { Object.assign(doc.tables.outbox.message, { recoveryCount: null, totalAttempts: 1 }); },
    doc => { Object.assign(doc.tables.outbox.message, { recoveryCount: 0.5, totalAttempts: 3.5 }); },
    doc => { doc.tables.outbox.message.members[0].future = true; },
    doc => { doc.tables.outbox.message.members[0].targetAt = 1; },
    doc => { doc.tables.outbox.message.members = []; },
    doc => { doc.tables.outbox.message.sessionId = null; },
  ]) {
    const changed = structuredClone(document);
    mutation(changed);
    fs.writeFileSync(target, JSON.stringify(changed));
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /Unknown.*schedule/);
    assert.deepEqual(state(f.home), before);
  }
});


test('unknown plugins and unreviewed mutable expressions cannot hide custom reference stores', async t => {
  for (const name of ['foo', '@third-party/custom', '@deepseek-ai/dsh-future-plugin', '@keewai/dsh-unreviewed']) {
    const f = fixture(t);
    f.write('profiles/web/cordis.patch.yml', `- insert:\n    - name: '${name}'\n      config:\n        root: /external/state\n`);
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /Unknown plugin package/);
    assert.deepEqual(state(f.home), before);
  }
  const f = fixture(t);
  f.write('profiles/web/cordis.patch.yml', '- id: ordinary\n  config:\n    scalar: !!js process.getBuiltinModule("node:fs").readFileSync("/external/refs")\n');
  await assert.rejects(f.preview('--gc-attachments'), /expression requires retention review/);
});

test('a partial owned workspace stage recovers only verified rollback or replacement prefixes', async t => {
  for (const foreign of [false, true]) {
    const f = fixture(t);
    const selected = f.session('selected'); f.session('retained');
    const { bytes } = workspaceFixture(f);
    const p = await f.preview('--id', 'selected');
    const write = fs.writeFileSync;
    const mock = t.mock.method(fs, 'writeFileSync', (target, data, ...args) => {
      if (typeof target === 'number' && fs.readlinkSync(`/proc/self/fd/${target}`).endsWith('/.retention-workspace.tmp')) {
        write(target, foreign ? Buffer.from('unrelated concurrent data') : data.subarray(0, 17), ...args);
        throw new Error('fixture partial stage write');
      }
      return write(target, data, ...args);
    });
    await assert.rejects(f.apply(p, '--id', 'selected'), foreign ? /Unknown interrupted workspace temporary file/ : /workspace selection metadata rolled back/);
    mock.mock.restore();
    assert.equal(fs.existsSync(selected.target), true);
    assert.equal(fs.readFileSync(path.join(f.home, 'storages/workspace.json'), 'utf8'), bytes);
    if (foreign) {
      assert.equal(fs.readFileSync(path.join(f.home, 'storages/.retention-workspace.tmp'), 'utf8'), 'unrelated concurrent data');
      await assert.rejects(run(['recover-workspace', '--home', f.home, '--confirm', 'RECOVER-WORKSPACE'], env), /Unknown interrupted workspace temporary file/);
    } else assert.equal(fs.existsSync(path.join(f.home, 'storages/.retention-workspace.json')), false);
  }
});


test('complete retained migration stages protect references and partial snapshots still refuse', async t => {
  t.mock.method(Date, 'now', () => future);
  const f = fixture(t);
  const preserved = f.attachment(Buffer.from('retained-migration-stage'));
  const transaction = 'b'.repeat(64);
  const data = JSON.stringify({ attachmentId: `sha256:${preserved.sha}` });
  for (const relative of [`operations/migrations/${transaction}/000001.stage`, `operations/migrations/${transaction}/.manifest.json-${'a'.repeat(16)}.tmp`, `operations/migrations/.active.json-${'a'.repeat(16)}.tmp`]) f.write(relative, data);
  assert.deepEqual((await f.preview('--gc-attachments')).plan.remove, []);
  f.write(`operations/migrations/${transaction}/source.bin`, data.slice(0, 17));
  await assert.rejects(f.preview('--gc-attachments'), /Malformed JSON/);
});


test('effective pinned patch composition resolves custom backend IDs through overrides and groups', async t => {
  const declaration = [{ insert: [{ id: 'custom-name', name: '@deepseek-ai/dsh-storage-json', config: { root: { fixture: true } } }] }];
  for (const nested of [false, true]) {
    const f = fixture(t);
    const rows = structuredClone(declaration);
    rows[0].insert[0].config.root = path.join(f.home, 'storages');
    if (nested) rows[0].insert = [{ id: 'outer', name: 'cordis:group', group: true, config: rows[0].insert }];
    f.write('profiles/web/cordis.patch.yml', JSON.stringify(rows));
    f.write('cordis.patch.yml', JSON.stringify([{ id: 'custom-name', config: { root: '/external/state' } }]));
    const before = state(f.home);
    await assert.rejects(f.preview('--gc-attachments'), /External or dynamic backend root/);
    assert.deepEqual(state(f.home), before);
  }
  const f = fixture(t);
  f.write('profiles/web/cordis.patch.yml', JSON.stringify([{ insert: [{ id: 'custom-name', name: '@deepseek-ai/dsh-storage-json', config: { root: path.join(f.home, 'storages') } }] }, { id: 'custom-name', config: { root: '/external/state' } }]));
  await assert.rejects(f.preview('--gc-attachments'), /External or dynamic backend root/);
});

test('each patch layer reindexes replaced group children before later alias overrides', async t => {
  const f = fixture(t);
  f.write('profiles/web/cordis.patch.yml', `- insert:\n    - id: outer\n      name: cordis:group\n      group: true\n      config: []\n- id: outer\n  config:\n    - id: custom-alias\n      name: '@deepseek-ai/dsh-storage-json'\n      config:\n        root: ${JSON.stringify(path.join(f.home, 'storages'))}\n`);
  f.write('cordis.patch.yml', '- id: custom-alias\n  config:\n    root: /external/state\n');
  const before = state(f.home);
  await assert.rejects(f.preview('--gc-attachments'), /External or dynamic backend root/);
  assert.deepEqual(state(f.home), before);
});
