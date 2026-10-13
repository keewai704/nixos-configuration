import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { run } from './migrate-cli.mjs';
import { hash, SafeTree } from './migrate-fs.mjs';
import { ACTIVE_PATH } from './migrate.mjs';
import { MAX_FILE } from './migrate-registry.mjs';

const base = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const env = { ...process.env };
const edge = 'session-projcache-v3-to-v7';
const source = 'storages/session_projcache.json';
const sessions = 'storages/session_projcache/sessions';
const legacy = () => ({ unit: { name: 'session_projcache', version: 3 }, global: null, tables: { sessions: {
  first: { identity: { createdAt: 1, cwd: '/fixture' }, rows: { title: { ver: 1, seq: 3, val: 'Original fixture' } } },
  second: { identity: { createdAt: 2 }, rows: { opaque: { ver: 1, seq: -1, val: JSON.parse('{"__proto__":{"a":true},"array":[0,null,"sha256:' + 'a'.repeat(64) + '"]}') } } },
} } });

function fixture(t, bytes = Buffer.from(JSON.stringify(legacy()))) {
  const root = fs.mkdtempSync(path.join(base, '.migrate-fixture-'));
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { mode: 0o700 });
  const write = (relative, data) => {
    const target = path.join(home, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
    fs.writeFileSync(target, data, { mode: 0o600 });
    return target;
  };
  write('.operations.lock', '');
  write(source, bytes);
  const plan = () => run(['plan', '--home', home, '--migration', edge], env);
  const apply = preview => run(['apply', '--home', home, '--migration', edge, '--plan-hash', preview.planHash, '--confirm', preview.confirmationToken], env);
  const recover = (transaction, action = 'recover') => run([action, '--home', home, '--transaction', transaction, '--confirm', `${action.toUpperCase()}:${transaction}`], env);
  t.after(() => {
    assert.equal(path.dirname(fs.realpathSync(root)), fs.realpathSync(base));
    assert.match(path.basename(root), /^\.migrate-fixture-/);
    fs.rmSync(root, { recursive: true });
  });
  return { root, home, write, plan, apply, recover, bytes, at: relative => path.join(home, relative) };
}

function state(home) {
  const result = [];
  const walk = relative => {
    const target = path.join(home, relative);
    const info = fs.lstatSync(target, { bigint: true });
    result.push([relative, String(info.ino), String(info.mode), String(info.nlink), String(info.size), String(info.mtimeNs), String(info.ctimeNs), info.isFile() ? hash(fs.readFileSync(target)) : null]);
    if (info.isDirectory()) for (const name of fs.readdirSync(target).sort()) walk(path.join(relative, name));
  };
  walk('');
  return result;
}

function inject(method, replacement, operation) {
  const original = fs[method];
  fs[method] = (...args) => replacement(original, ...args);
  try { return operation(); }
  finally { fs[method] = original; }
}

function interruptAfterFirstTarget(f, plan) {
  return inject('renameSync', (original, from, to) => {
    original(from, to);
    if (String(from).endsWith('/000000.stage')) throw new Error('fixture crash after first publication');
  }, () => assert.throws(() => f.apply(plan), /fixture crash/));
}

test('plan is read-only; confirmed apply splits real persisted shape with immutable byte snapshots', t => {
  const f = fixture(t);
  const before = state(f.home);
  const preview = f.plan();
  assert.deepEqual(state(f.home), before);
  assert.equal(f.plan().planHash, preview.planHash);
  const result = f.apply(preview);
  assert.equal(result.status, 'COMMITTED');
  assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
  assert.deepEqual(fs.readFileSync(f.at(source)), f.bytes);
  assert.deepEqual(fs.readFileSync(f.at(`operations/migrations/${result.transaction}/source.bin`)), f.bytes);
  assert.equal(fs.statSync(f.at(`operations/migrations/${result.transaction}/source.bin`)).mode & 0o777, 0o400);
  for (const id of ['first', 'second']) {
    const document = JSON.parse(fs.readFileSync(f.at(`${sessions}/${id}.json`)));
    assert.equal(document.version, 7);
    assert.deepEqual(document.record, legacy().tables.sessions[id]);
    assert.equal(Object.hasOwn(document.record.identity, 'formatVersion'), false);
  }
  const manifest = JSON.parse(fs.readFileSync(f.at(result.manifest)));
  assert.equal(manifest.status, 'COMMITTED');
  assert.throws(() => f.plan(), /Existing per-record content/);
  f.recover(result.transaction, 'rollback');
  assert.deepEqual(fs.readdirSync(f.at(sessions)), []);
  assert.deepEqual(fs.readFileSync(f.at(source)), f.bytes);
  assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
  assert.equal(JSON.parse(fs.readFileSync(f.at(result.manifest))).status, 'ROLLED_BACK');
  assert.equal(f.recover(result.transaction).status, 'ROLLED_BACK');
});

test('missing lock, unknown schema, existing tree, wrong confirmation and stale plan refuse without mutations', t => {
  const f = fixture(t);
  const original = f.plan();
  const before = state(f.home);
  assert.throws(() => run(['apply', '--home', f.home, '--migration', edge, '--plan-hash', original.planHash, '--confirm', 'yes'], env), /exact/);
  assert.deepEqual(state(f.home), before);
  f.write(source, JSON.stringify({ ...legacy(), unexpected: true }));
  assert.throws(() => f.plan(), /Unsupported schema field/);
  f.write(source, `${f.bytes}\n`);
  const stale = state(f.home);
  assert.throws(() => f.apply(original), /Plan hash mismatch/);
  assert.deepEqual(state(f.home), stale);
  f.write(`${sessions}/foreign.json`, '{"version":99}');
  assert.throws(() => f.plan(), /Existing per-record content/);
  const other = fixture(t);
  const lock = other.at('.operations.lock');
  assert.equal(fs.realpathSync(lock), lock);
  fs.unlinkSync(lock);
  const absent = state(other.home);
  assert.throws(() => other.plan(), /ENOENT/);
  assert.deepEqual(state(other.home), absent);
});

test('shared packaged-writer lock blocks every migration action', t => {
  const f = fixture(t);
  const preview = f.plan();
  const fd = fs.openSync(f.at('.operations.lock'), 'r');
  try {
    const held = spawnSync(env.DSH_MIGRATE_FLOCK ?? env.DSH_RETENTION_FLOCK, ['--shared', '--nonblock', '3'], { stdio: ['ignore', 'pipe', 'pipe', fd] });
    assert.equal(held.status, 0, held.stderr?.toString());
    const before = state(f.home);
    assert.throws(() => f.plan(), /Live .operations.lock/);
    assert.throws(() => f.apply(preview), /Live .operations.lock/);
    assert.deepEqual(state(f.home), before);
  } finally { fs.closeSync(fd); }
});

test('every publication has durable PREPARED gate, fsynced bytes and terminal commit ordering', t => {
  const f = fixture(t);
  const preview = f.plan();
  const events = [];
  const originalSync = fs.fsyncSync;
  fs.fsyncSync = fd => { events.push(['sync', fs.readlinkSync(`/proc/self/fd/${fd}`)]); return originalSync(fd); };
  try {
    inject('renameSync', (original, from, to) => {
      const name = String(from);
      if (name.endsWith('.stage')) {
        const active = JSON.parse(fs.readFileSync(f.at(ACTIVE_PATH)));
        const manifest = JSON.parse(fs.readFileSync(f.at(active.manifest)));
        assert.equal(manifest.status, 'PREPARED');
        assert.equal(fs.statSync(from).nlink, 1);
        assert.ok(events.some(([kind, file]) => kind === 'sync' && file.endsWith(path.basename(from))));
      }
      events.push(['rename', fs.realpathSync(path.dirname(to)), path.basename(to)]);
      original(from, to);
    }, () => f.apply(preview));
  } finally { fs.fsyncSync = originalSync; }
  for (let i = 0; i < events.length; i++) {
    if (events[i][0] === 'rename' && ['first.json', 'second.json'].includes(events[i][2])) assert.equal(events[i + 1][0], 'sync');
  }
});

test('crash after atomic publication leaves gate and recovers only expected bytes', t => {
  const f = fixture(t);
  const preview = f.plan();
  interruptAfterFirstTarget(f, preview);
  assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
  assert.ok(fs.existsSync(f.at(`${sessions}/first.json`)));
  assert.equal(fs.existsSync(f.at(`${sessions}/second.json`)), false);
  assert.throws(() => f.plan(), /Active migration gate/);
  const result = f.recover(preview.planHash);
  assert.equal(result.status, 'ROLLED_BACK');
  assert.deepEqual(fs.readdirSync(f.at(sessions)), []);
  assert.deepEqual(fs.readFileSync(f.at(source)), f.bytes);
  assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
});

test('recovery preflight refuses any unrelated modified target without rolling back others', t => {
  const f = fixture(t);
  const preview = f.plan();
  f.apply(preview);
  f.write(`${sessions}/second.json`, 'unrelated concurrent update');
  const before = state(f.home);
  assert.throws(() => f.recover(preview.planHash, 'rollback'), /Unrelated concurrent modification/);
  assert.deepEqual(state(f.home), before);
});

test('corrupt snapshot, changed source inode and malicious manifest path never regain write authority', t => {
  for (const modification of ['snapshot', 'source', 'path']) {
    const f = fixture(t);
    const preview = f.plan();
    interruptAfterFirstTarget(f, preview);
    const root = `operations/migrations/${preview.planHash}`;
    if (modification === 'snapshot') {
      fs.chmodSync(f.at(`${root}/source.bin`), 0o600);
      f.write(`${root}/source.bin`, 'corrupt');
    } else if (modification === 'source') {
      const replacement = f.write('storages/replacement', f.bytes);
      assert.equal(fs.realpathSync(f.at(source)), f.at(source));
      fs.renameSync(replacement, f.at(source));
    } else {
      const manifest = JSON.parse(fs.readFileSync(f.at(`${root}/manifest.json`)));
      manifest.plan.files[0].path = '../outside.json';
      f.write(`${root}/manifest.json`, JSON.stringify(manifest));
    }
    const before = state(f.home);
    assert.throws(() => f.recover(preview.planHash), /snapshot|changed|hash mismatch/);
    assert.deepEqual(state(f.home), before);
  }
});

test('a crash after COMMITTED finalizes the durable gate without rolling back committed files', t => {
  const f = fixture(t);
  const preview = f.plan();
  inject('unlinkSync', (original, file) => {
    if (String(file).endsWith('/active.json')) throw new Error('fixture crash before clearing gate');
    original(file);
  }, () => assert.throws(() => f.apply(preview), /fixture crash/));
  assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
  assert.equal(f.recover(preview.planHash).status, 'COMMITTED');
  assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
  assert.ok(fs.existsSync(f.at(`${sessions}/second.json`)));
});

test('rollback itself is durable, gated and restartable after partial removal', t => {
  const f = fixture(t);
  const preview = f.plan();
  f.apply(preview);
  inject('unlinkSync', (original, file) => {
    original(file);
    if (String(file).endsWith('/first.json')) throw new Error('fixture rollback crash');
  }, () => assert.throws(() => f.recover(preview.planHash, 'rollback'), /fixture rollback crash/));
  assert.equal(fs.existsSync(f.at(`${sessions}/first.json`)), false);
  assert.ok(fs.existsSync(f.at(`${sessions}/second.json`)));
  assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
  assert.equal(f.recover(preview.planHash).status, 'ROLLED_BACK');
  assert.deepEqual(fs.readdirSync(f.at(sessions)), []);
});

test('unsafe links, roots, file types, permissions, size and inode changes fail closed', t => {
  for (const variation of ['symlink', 'hardlink', 'directory', 'permissions', 'size', 'lock-link', 'root-link']) {
    const f = fixture(t);
    if (variation === 'symlink') {
      const target = f.write('outside', f.bytes);
      assert.equal(fs.realpathSync(f.at(source)), f.at(source));
      fs.unlinkSync(f.at(source));
      fs.symlinkSync(target, f.at(source));
    } else if (variation === 'hardlink') fs.linkSync(f.at(source), f.at('alias'));
    else if (variation === 'lock-link') fs.linkSync(f.at('.operations.lock'), f.at('lock-alias'));
    else if (variation === 'directory') {
      assert.equal(fs.realpathSync(f.at(source)), f.at(source));
      fs.unlinkSync(f.at(source));
      fs.mkdirSync(f.at(source));
    } else if (variation === 'permissions') fs.chmodSync(f.at(source), 0o666);
    else if (variation === 'size') fs.truncateSync(f.at(source), MAX_FILE + 1);
    else {
      fs.symlinkSync(f.home, path.join(f.root, 'link'));
      assert.throws(() => run(['plan', '--home', path.join(f.root, 'link'), '--migration', edge], env), /symlink/);
      continue;
    }
    assert.throws(() => f.plan(), /Unsafe|hardlink|bounded/);
  }
  const f = fixture(t);
  const tree = new SafeTree(f.home);
  try {
    tree.directory('storages');
    const replacement = f.at('replaced');
    assert.equal(fs.realpathSync(f.at('storages')), f.at('storages'));
    fs.renameSync(f.at('storages'), replacement);
    fs.mkdirSync(f.at('storages'));
    assert.throws(() => tree.read(source), /inode changed/);
  } finally { tree.close(); }
});

test('metadata and target directory symlinks cannot redirect publication', t => {
  const f = fixture(t);
  const outside = path.join(f.root, 'outside');
  fs.mkdirSync(outside, { mode: 0o700 });
  fs.symlinkSync(outside, f.at('operations'));
  assert.throws(() => f.plan(), /Unsafe/);
  assert.deepEqual(fs.readdirSync(outside), []);
  const other = fixture(t);
  fs.symlinkSync(outside, other.at('storages/session_projcache'));
  assert.throws(() => other.plan(), /Unsafe/);
});

test('strict CLI refuses contradictory or executable transformation options without reading data', () => {
  for (const args of [[], ['plan'], ['plan', '--home', '/unused', '--migration', edge, '--transform', '/arbitrary.mjs'], ['plan', '--home', '/unused', '--migration', edge, '--confirm', 'yes'], ['plan', '--home', '/unused', '--home', '/other', '--migration', edge]]) assert.throws(() => run(args, env));
});

test('preparation crashes before directory, manifest, snapshots, and PREPARED remain recoverable without deleting metadata', t => {
  for (const boundary of ['gate', 'directory', 'manifest', 'snapshot', 'stage', 'prepared']) {
    const f = fixture(t);
    const preview = f.plan();
    let tripped = false;
    const trap = (original, ...args) => {
      const result = original(...args);
      const file = String(args[0]);
      const active = fs.existsSync(f.at(ACTIVE_PATH));
      if (!tripped && active && (
        boundary === 'gate' && String(args[1]).endsWith('/active.json') ||
        boundary === 'directory' && file.endsWith(`/${preview.planHash}`) ||
        boundary === 'manifest' && String(args[1]).endsWith('/manifest.json') ||
        boundary === 'snapshot' && typeof args[0] === 'number' && fs.readlinkSync(`/proc/self/fd/${args[0]}`).endsWith('/source.bin') ||
        boundary === 'stage' && typeof args[0] === 'number' && fs.readlinkSync(`/proc/self/fd/${args[0]}`).endsWith('/000000.stage') ||
        boundary === 'prepared' && String(args[1]).endsWith('/manifest.json') && JSON.parse(fs.readFileSync(args[1])).status === 'PREPARED'
      )) { tripped = true; throw new Error(`fixture fault at ${boundary}`); }
      return result;
    };
    const method = boundary === 'directory' ? 'mkdirSync' : ['snapshot', 'stage'].includes(boundary) ? 'writeFileSync' : 'renameSync';
    inject(method, trap, () => assert.throws(() => f.apply(preview), /fixture fault/));
    assert.ok(tripped);
    assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
    assert.equal(fs.existsSync(f.at(`${sessions}/first.json`)), false);
    const recovered = f.recover(preview.planHash);
    assert.equal(recovered.status, boundary === 'prepared' ? 'ROLLED_BACK' : 'ABORTED');
    assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
    assert.deepEqual(fs.readFileSync(f.at(source)), f.bytes);
    const next = f.plan();
    assert.notEqual(next.planHash, preview.planHash);
    assert.equal(f.apply(next).status, 'COMMITTED');
  }
});

test('recovery syncs a target directory even when last rollback unlink happened before its fsync', t => {
  const f = fixture(t);
  const preview = f.plan();
  f.apply(preview);
  inject('unlinkSync', (original, file) => {
    original(file);
    if (String(file).endsWith('/second.json')) throw new Error('fault after last unlink before directory fsync');
  }, () => assert.throws(() => f.recover(preview.planHash, 'rollback'), /fault after last/));
  assert.deepEqual(fs.readdirSync(f.at(sessions)), []);
  const synced = [];
  const original = fs.fsyncSync;
  fs.fsyncSync = fd => { synced.push(fs.readlinkSync(`/proc/self/fd/${fd}`)); return original(fd); };
  try {
    inject('unlinkSync', (unlink, file) => {
      if (String(file).endsWith('/active.json')) assert.ok(synced.includes(f.at(sessions)));
      unlink(file);
    }, () => f.recover(preview.planHash));
  } finally { fs.fsyncSync = original; }
  assert.ok(synced.includes(f.at(sessions)));
});

test('unfinished retention workspace journals block all actions before any migration writes', t => {
  for (const journal of ['storages/.retention-workspace.json', 'storages/.retention-workspace.tmp']) {
    for (const type of ['file', 'symlink']) {
      const f = fixture(t);
      const preview = f.plan();
      if (type === 'file') f.write(journal, 'malformed interrupted retention');
      else fs.symlinkSync('/does-not-exist', f.at(journal));
      const before = state(f.home);
      for (const action of [() => f.plan(), () => f.apply(preview), () => f.recover(preview.planHash), () => f.recover(preview.planHash, 'rollback')]) assert.throws(action, /retention|Unsafe/);
      assert.deepEqual(state(f.home), before);
    }
  }
});

test('an I/O failure before target directory fsync leaves PREPARED and recovery syncs before clearing the gate', t => {
  const f = fixture(t);
  const preview = f.plan();
  let published = false;
  const originalSync = fs.fsyncSync;
  fs.fsyncSync = fd => {
    if (published && fs.readlinkSync(`/proc/self/fd/${fd}`) === f.at(sessions)) throw new Error('fixture EIO syncing target directory');
    return originalSync(fd);
  };
  try {
    inject('renameSync', (rename, from, to) => {
      rename(from, to);
      if (String(from).endsWith('/000000.stage')) published = true;
    }, () => assert.throws(() => f.apply(preview), /fixture EIO/));
  } finally { fs.fsyncSync = originalSync; }
  assert.equal(JSON.parse(fs.readFileSync(f.at(`operations/migrations/${preview.planHash}/manifest.json`))).status, 'PREPARED');
  assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
  assert.equal(f.recover(preview.planHash).status, 'ROLLED_BACK');
});

test('COMMITTED recovery syncs the manifest directory after a crash between rename and directory fsync', t => {
  const f = fixture(t);
  const preview = f.plan();
  inject('renameSync', (rename, from, to) => {
    rename(from, to);
    if (String(to).endsWith('/manifest.json') && JSON.parse(fs.readFileSync(to)).status === 'COMMITTED') throw new Error('fixture terminal rename crash');
  }, () => assert.throws(() => f.apply(preview), /fixture terminal rename crash/));
  const synced = [];
  const original = fs.fsyncSync;
  fs.fsyncSync = fd => { synced.push(fs.readlinkSync(`/proc/self/fd/${fd}`)); return original(fd); };
  try {
    inject('unlinkSync', (unlink, file) => {
      if (String(file).endsWith('/active.json')) assert.ok(synced.includes(f.at(`operations/migrations/${preview.planHash}`)));
      unlink(file);
    }, () => assert.equal(f.recover(preview.planHash).status, 'COMMITTED'));
  } finally { fs.fsyncSync = original; }
});

test('bounded read rejects a file that grows after open instead of consuming unbounded bytes', t => {
  const f = fixture(t);
  let bytesRead = 0;
  let expanded = false;
  inject('readSync', (read, fd, buffer, offset, length, position) => {
    if (!expanded && fs.readlinkSync(`/proc/self/fd/${fd}`) === f.at(source)) {
      expanded = true;
      fs.appendFileSync(f.at(source), Buffer.alloc(1024));
    }
    const count = read(fd, buffer, offset, length, position);
    bytesRead += count;
    return count;
  }, () => assert.throws(() => f.plan(), /changed during bounded read/));
  assert.equal(bytesRead, f.bytes.length + 1);
});

test('storage and operations lock inode replacements during I/O never authorize writes', t => {
  for (const target of ['storages', '.operations.lock']) {
    const f = fixture(t);
    const preview = f.plan();
    let replaced = false;
    inject('readSync', (read, fd, ...args) => {
      const result = read(fd, ...args);
      if (!replaced && fs.readlinkSync(`/proc/self/fd/${fd}`) === f.at(source)) {
        replaced = true;
        const original = f.at(target);
        assert.equal(fs.realpathSync(original), original);
        fs.renameSync(original, f.at('original-entry'));
        if (target === 'storages') fs.mkdirSync(original, { mode: 0o700 });
        else fs.writeFileSync(original, '', { mode: 0o600 });
      }
      return result;
    }, () => assert.throws(() => f.apply(preview), /inode changed/));
    assert.equal(fs.existsSync(f.at(ACTIVE_PATH)), false);
  }
});

test('SIGKILL during publication leaves a durable gate and another process can recover', t => {
  const f = fixture(t);
  const preview = f.plan();
  const cli = new URL('./migrate-cli.mjs', import.meta.url).href;
  const code = `import fs from 'node:fs'; import {run} from ${JSON.stringify(cli)}; const original=fs.renameSync; fs.renameSync=(from,to)=>{original(from,to);if(String(from).endsWith('/000000.stage')) process.kill(process.pid,'SIGKILL')}; run(${JSON.stringify(['apply', '--home', f.home, '--migration', edge, '--plan-hash', preview.planHash, '--confirm', preview.confirmationToken])});`;
  const killed = spawnSync(process.execPath, ['--input-type=module', '--eval', code], { env, encoding: 'utf8' });
  assert.equal(killed.signal, 'SIGKILL', killed.stderr);
  assert.ok(fs.existsSync(f.at(ACTIVE_PATH)));
  assert.equal(f.recover(preview.planHash).status, 'ROLLED_BACK');
  assert.deepEqual(fs.readdirSync(f.at(sessions)), []);
});

test('archived pinned fixture becomes documents accepted by real pinned storage and cache schemas', { skip: !env.DSH_MIGRATE_PINNED_SOURCE || !env.DSH_MIGRATE_NODE_MODULES }, async t => {
  const archived = fs.readFileSync(path.join(env.DSH_MIGRATE_PINNED_SOURCE, 'packages/session/session-projection-cache/tests/fixtures/v3-single-unit.json'));
  const f = fixture(t, archived);
  const preview = f.plan();
  f.apply(preview);
  const module = name => import(pathToFileURL(path.join(env.DSH_MIGRATE_NODE_MODULES, '@deepseek-ai', name, 'lib/index.js')).href);
  const { JsonStorageBackend } = await module('dsh-storage-json');
  const { checkpointRecord, projectionCacheDomainSpec } = await module('dsh-session-projection-cache');
  const backend = new JsonStorageBackend(f.at('storages'));
  const unit = await backend.kv.open({ name: projectionCacheDomainSpec.name, version: projectionCacheDomainSpec.version, compatibleVersions: projectionCacheDomainSpec.compatibleVersions, layout: projectionCacheDomainSpec.layout, tables: ['sessions'], hasGlobal: false });
  try {
    const loaded = await unit.loadAll();
    const original = JSON.parse(archived);
    assert.deepEqual(loaded.tables.sessions, original.tables.sessions);
    for (const record of Object.values(loaded.tables.sessions)) {
      assert.deepEqual(checkpointRecord.parse(record), record);
      assert.equal(Object.hasOwn(record.identity, 'formatVersion'), false);
    }
  } finally { await unit.close(); await backend.close(); }
});
