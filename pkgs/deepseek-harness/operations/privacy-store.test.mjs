import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, chmodSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import { PrivacyStore, PRIVACY_CHANNELS } from './privacy-store.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'dsh-privacy-test-'));
  const stores = [];
  t.after(() => {
    for (const store of stores) store.close();
    assert.equal(realpathSync(root), root);
    assert.match(root, /\/dsh-privacy-test-[^/]+$/);
    rmSync(root, { recursive: true });
  });
  return { root, open() { const store = new PrivacyStore(join(root, 'operations')); stores.push(store); return store; } };
}

test('all channels default off and committed consent survives restart', t => {
  const f = fixture(t);
  const first = f.open();
  for (const id of PRIVACY_CHANNELS) assert.deepEqual(first.get(id), { enabled: false, revision: 0, updatedAt: 0 });
  first.set(PRIVACY_CHANNELS[0], true, 0, `ENABLE ${PRIVACY_CHANNELS[0]}`);
  const second = f.open();
  assert.equal(second.get(PRIVACY_CHANNELS[0]).enabled, true);
  assert.equal(second.get(PRIVACY_CHANNELS[0]).revision, 1);
  second.set(PRIVACY_CHANNELS[0], false, 1, `DISABLE ${PRIVACY_CHANNELS[0]}`);
  assert.equal(first.get(PRIVACY_CHANNELS[0]).enabled, false);
});

test('confirmation and cross-process compare-and-swap prevent stale consent', t => {
  const f = fixture(t); const a = f.open(); const b = f.open(); const id = PRIVACY_CHANNELS[1];
  assert.throws(() => a.set(id, true, 0, 'YES'), /Explicit/);
  a.set(id, true, 0, `ENABLE ${id}`);
  assert.throws(() => b.set(id, false, 0, `DISABLE ${id}`), /changed/);
  assert.equal(b.get(id).enabled, true);
  assert.throws(() => b.set(id, true, '1', `ENABLE ${id}`), /Invalid/);
  assert.throws(() => a.get('other'), /Unknown/);
});

test('reseeded managed profile cannot reset independent persisted policy', t => {
  const f = fixture(t); const a = f.open(); const id = PRIVACY_CHANNELS[2];
  a.set(id, true, 0, `ENABLE ${id}`);
  mkdirSync(join(f.root, 'profiles'));
  writeFileSync(join(f.root, 'profiles', 'cordis.patch.yml'), 'enabled: false\n');
  assert.equal(f.open().get(id).enabled, true);
});

test('same choice is a no-op and updated decisions increase revisions', t => {
  const f = fixture(t); const a = f.open(); const id = PRIVACY_CHANNELS[3];
  assert.equal(a.set(id, false, 0, `DISABLE ${id}`).revision, 0);
  assert.equal(a.set(id, true, 0, `ENABLE ${id}`).revision, 1);
  assert.equal(a.set(id, true, 1, `ENABLE ${id}`).revision, 1);
});

test('symlinked and public databases are refused', t => {
  const f = fixture(t); mkdirSync(join(f.root, 'operations'));
  const outside = join(f.root, 'external'); writeFileSync(outside, '');
  symlinkSync(outside, join(f.root, 'operations', 'privacy.sqlite'));
  assert.throws(() => f.open(), /ELOOP/);
  const other = join(f.root, 'public'); mkdirSync(other); writeFileSync(join(other, 'privacy.sqlite'), '', { mode: 0o644 });
  assert.throws(() => new PrivacyStore(other), /Unsafe/);
});

test('world-writable store and unknown database generations fail closed', t => {
  const f = fixture(t); const directory = join(f.root, 'operations'); mkdirSync(directory); chmodSync(directory, 0o777);
  assert.throws(() => f.open(), /Unsafe/);
  chmodSync(directory, 0o700);
  const file = join(directory, 'privacy.sqlite');
  writeFileSync(file, '', { mode: 0o600 });
  const db = new DatabaseSync(file); db.exec('PRAGMA user_version=2'); db.close();
  assert.throws(() => f.open(), /Unsupported/);
});
