import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const [workspace, source, output, revision, hash] = process.argv.slice(2);
if (process.argv.length !== 7) {
  throw new Error('Usage: node --import tsx build.mjs HYDRATED_WORKSPACE PINNED_SOURCE OUTPUT REVISION HASH');
}
const patch = spawnSync('patch', [
  '--batch', '--forward', '--fuzz=0', '-p1', '-i',
  fileURLToPath(new URL('./generator.patch', import.meta.url)),
], { cwd: workspace, stdio: 'inherit' });
if (patch.error) throw patch.error;
if (patch.status !== 0) throw new Error(`Catalog generator patch failed: ${patch.status}`);
const { collectConfigCatalog } = await import(pathToFileURL(join(workspace, 'scripts/gen-config-catalog.ts')).href);
const entries = collectConfigCatalog(source);
writeFileSync(output, `${JSON.stringify({ source: { revision, hash }, entries }, null, 2)}\n`);
