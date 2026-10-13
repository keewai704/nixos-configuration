import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const [bundle, kernelModules, output] = process.argv.slice(2);
if (![bundle, kernelModules, output].every(value => value && isAbsolute(value))) {
  throw new Error('Usage: node installed-import.mjs BUNDLE KERNEL_NODE_MODULES NEW_OUTPUT');
}
if (existsSync(output)) throw new Error('Installed-import output must not exist');
const target = join(output, 'node_modules/@keewai/dsh-reliability');
mkdirSync(target, { recursive: true });
for (const name of ['lib', 'package.json', 'LICENSE']) cpSync(join(bundle, name), join(target, name), { recursive: true });
const manifest = JSON.parse(readFileSync(join(target, 'package.json'), 'utf8'));
assert.equal(manifest.peerDependencies['@agentclientprotocol/sdk'], undefined);
assert.match(readFileSync(join(target, manifest.bundledDependencyProvenance['@agentclientprotocol/sdk'].licenseFile), 'utf8'), /Apache License/);
const peers = createRequire(join(kernelModules, 'package.json'));
for (const name of Object.keys(manifest.peerDependencies)) {
  let path = join(kernelModules, name);
  if (!existsSync(path)) {
    try { path = dirname(peers.resolve(`${name}/package.json`)); }
    catch { continue; }
  }
  const link = join(output, 'node_modules', name);
  mkdirSync(dirname(link), { recursive: true });
  symlinkSync(path, link);
}
assert.equal(existsSync(join(output, 'node_modules/@agentclientprotocol')), false);
const script = join(output, 'verify-installed.mjs');
writeFileSync(script, `import assert from 'node:assert/strict';\nimport { createRequire } from 'node:module';\nconst require = createRequire(import.meta.url);\nassert.throws(() => require.resolve('@agentclientprotocol/sdk'));\nfor (const entry of ['workflow','schedule','subagents','acp','approval','approval-journal']) {\n  const loaded = await import('@keewai/dsh-reliability/' + entry);\n  assert.ok(typeof loaded.default === 'function' || typeof loaded.apply === 'function');\n  console.log('Installed provider imported without SDK package: ' + entry);\n}\n`);
const result = spawnSync(process.execPath, [script], { cwd: resolve(output), stdio: 'inherit', env: { ...process.env, NODE_PATH: '' } });
if (result.status !== 0) process.exit(result.status ?? 1);
