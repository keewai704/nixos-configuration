import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const usage = 'Usage: dsh-config-catalog [--format json]\nReads a static catalog generated from pinned DSH source at build time.';
if (args.length === 1 && args[0] === '--help') {
  console.log(usage);
} else if (args.length === 0 || (args.length === 2 && args[0] === '--format' && args[1] === 'json')) {
  const text = readFileSync(new URL('./catalog.json', import.meta.url), 'utf8');
  if (args.length) {
    process.stdout.write(text);
  } else {
    const { source, entries } = JSON.parse(text);
    const counts = new Map();
    for (const { kind } of entries) counts.set(kind, (counts.get(kind) ?? 0) + 1);
    console.log(`DSH config catalog: ${entries.length} packages`);
    console.log(`Source: ${source.revision} (${source.hash})`);
    for (const kind of ['config', 'no-config', 'seam', 'library']) console.log(`${kind}: ${counts.get(kind) ?? 0}`);
    console.log('Use --format json for the complete catalog.');
  }
} else {
  console.error(usage);
  process.exitCode = 2;
}
