import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

export async function buildComposition(source, kernel) {
  const require = createRequire(join(kernel, 'package.json'));
  const yaml = require('js-yaml');
  const { entryListSchema, applyEntryPatches } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis-plugin-include')).href);
  const load = file => yaml.load(readFileSync(file, 'utf8'), { schema: entryListSchema });
  const layers = ['packages/bundle/base/cordis.patch.yml', 'packages/bundle/web-app/cordis.patch.yml', ...['standard', 'ptc', 'minimal', 'cordis'].map(name => `packages/bundle/web-app/presets/${name}.patch.yml`)];
  const original = layers.reduce((rows, file) => applyEntryPatches(rows, load(join(source, file)), message => { throw new Error(message); }), []);
  const byId = new Map();
  const index = rows => { for (const row of rows) { byId.set(row.id, row); if (row.group && Array.isArray(row.config)) index(row.config); } };
  index(original);
  const intents = load(new URL('./cordis.patch.yml', import.meta.url));
  const patches = intents.flatMap(patch => {
    if (!patch.id || !patch.name) return [patch];
    const previous = byId.get(patch.id);
    if (!previous) throw new Error(`Missing replacement target ${patch.id}`);
    if (previous.name === patch.name) return [patch];
    const replacement = { ...structuredClone(previous), ...patch, id: `operations-${patch.id}` };
    return [{ id: patch.id, disabled: true }, { insert: [replacement] }];
  });
  function transform(rows) {
    for (const row of rows) {
      if (row.name === '@deepseek-ai/dsh-workflow-ptc') {
        row.name = '@keewai/dsh-reliability/workflow';
        row.inject = { ...(row.inject ?? {}), budgetPolicy: {} };
        row.config = { ...row.config, requireJournal: true, timeoutMs: 3600000, maxTotalAgents: 128, maxConcurrentAgents: 8 };
      }
      if (row.group && Array.isArray(row.config)) transform(row.config);
    }
  }
  for (const name of ['standard', 'ptc', 'cordis']) {
    const file = join(source, 'packages/bundle/web-app/presets', `${name}.patch.yml`);
    const declarations = yaml.load(readFileSync(file, 'utf8'), { schema: entryListSchema });
    const preset = declarations.flatMap(patch => patch.insert ?? []).find(row => row.id === `preset-${name}`);
    if (!preset || !Array.isArray(preset.config?.plugins)) throw new Error(`Invalid pinned preset ${name}`);
    transform(preset.config.plugins);
    preset.config.plugins.push({ id: 'checkpoint-tools', name: '@keewai/dsh-operations/checkpoint-tools' });
    preset.config.plugins.push({ id: 'message-policy', name: '@keewai/dsh-operations/message-policy' });
    patches.push({ id: preset.id, config: preset.config });
  }
  return yaml.dump(patches, { schema: entryListSchema, noRefs: true, lineWidth: -1 });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [source, kernel, output] = process.argv.slice(2);
  if (!source || !kernel || !output || existsSync(output)) throw new Error('Supply pinned source, kernel root and a new patch output');
  writeFileSync(output, await buildComposition(source, kernel));
}
