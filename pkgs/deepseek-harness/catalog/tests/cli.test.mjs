import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const root = process.env.DSH_CATALOG_PACKAGE;
assert.ok(root, 'DSH_CATALOG_PACKAGE must identify the installed package');
const run = (...args) => spawnSync(join(root, 'bin/dsh-config-catalog'), args, { encoding: 'utf8', cwd: tmpdir() });
const artifact = readFileSync(join(root, 'share/dsh-config/catalog.json'), 'utf8');
const { source, entries } = JSON.parse(artifact);

test('JSON output is the complete pinned artifact, independent of the working directory', () => {
  const result = run('--format', 'json');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, artifact);
  assert.ok(source.revision.length > 0);
  assert.match(source.hash, /^sha256-/);
  assert.ok(entries.length > 0);
  assert.equal(new Set(entries.map(entry => entry.pkg)).size, entries.length);
  assert.deepEqual(new Set(entries.map(entry => entry.kind)), new Set(['config', 'no-config', 'seam', 'library']));
});

test('the real re-exported TypertRegistry is retained as a no-config plugin', () => {
  assert.deepEqual(entries.find(entry => entry.pkg === '@deepseek-ai/dsh-typert-registry'), {
    pkg: '@deepseek-ai/dsh-typert-registry',
    dir: 'packages/typert/registry',
    entry: 'packages/typert/registry/src/index.ts',
    kind: 'no-config',
    inject: [],
    className: 'TypertRegistry',
  });
});

test('the default summary reports the catalog classifications', () => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.ok(result.stdout.includes(`${entries.length} packages`));
  assert.ok(result.stdout.includes(source.revision));
  for (const kind of new Set(entries.map(entry => entry.kind))) {
    assert.ok(result.stdout.includes(`${kind}: ${entries.filter(entry => entry.kind === kind).length}\n`));
  }
});

test('help describes the static build-time artifact', () => {
  const result = run('--help');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.match(result.stdout, /static catalog/);
});

test('unsupported arguments fail without emitting a catalog', () => {
  for (const args of [['--format'], ['--format', 'yaml'], ['--source', '.'], ['--format', 'json', 'extra']]) {
    const result = run(...args);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Usage: dsh-config-catalog/);
  }
});
