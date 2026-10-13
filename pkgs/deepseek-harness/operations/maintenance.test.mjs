import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import * as zlib from 'node:zlib';
import { run } from './maintenance.mjs';

const base = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
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

test('workspace metadata is preserved and reported, legacy rehydration is refused', async t => {
  const f = fixture(t);
  f.session('selected');
  const workspace = { unit: { name: 'workspace', version: 2 }, global: { initialized: true, workspaceIds: ['work'], pinnedSessionIds: ['selected'] }, tables: { workspaces: { work: { path: '/fixture', title: 'Fixture', createdAt: '2020-01-01', updatedAt: '2020-01-01', sessionIds: ['selected'] } } } };
  f.write('storages/workspace.json', JSON.stringify(workspace));
  const p = await f.preview('--id', 'selected');
  assert.deepEqual(p.plan.leftovers.workspaceSessionIds, ['selected']);
  await f.apply(p, '--id', 'selected');
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.home, 'storages/workspace.json'), 'utf8')), workspace);
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
