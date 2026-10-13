import { chmodSync, cpSync, mkdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));

export function prepareAcp(source, output) {
  const target = join(output, 'acp');
  mkdirSync(target, { recursive: false });
  for (const name of ['index.ts', 'run.ts']) {
    const original = join(source, 'packages/subagent/subagent-acp/src', name);
    const expected = JSON.parse(readFileSync(join(here, 'source-hashes.json'), 'utf8'))[name];
    if (createHash('sha256').update(readFileSync(original)).digest('hex') !== expected) throw new Error(`Pinned ACP source changed: ${name}`);
    cpSync(original, join(target, name));
    chmodSync(join(target, name), 0o644);
  }
  const patched = spawnSync('patch', ['-p1', '--batch', '-i', join(here, 'provider.patch')], { cwd: output, stdio: 'inherit' });
  if (patched.status !== 0) throw new Error('ACP replacement source patch failed');
  for (const name of ['parent-approval.ts', 'approval.ts', 'approval-journal.ts', 'approval-journal-plugin.ts']) cpSync(join(here, name), join(target, name));
}
