import { cpSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolution, checkOwned } from './build-support.mjs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const here = dirname(fileURLToPath(import.meta.url));
const [source, dependencySource, output] = process.argv.slice(2).map(value => resolve(value));
if (!source || !dependencySource || !output) throw new Error('Usage: node verify.mjs SOURCE DEPENDENCY_SOURCE NEW_OUTPUT');
function run(command, args, cwd = output) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
run(process.execPath, [join(here, 'build.mjs'), source, dependencySource, join(dependencySource, 'node_modules'), output, 'prepare'], here);
const ts = (await import(pathToFileURL(join(dependencySource, 'node_modules/typescript/lib/typescript.js')).href)).default;
const compilerOptions = resolution(ts, source, dependencySource, output);
compilerOptions.rewriteRelativeImportExtensions = false;
const { paths } = compilerOptions;
cpSync(join(here, 'tests'), join(output, 'tests'), { recursive: true });
cpSync(join(source, 'packages/core/agent-loop/tests/mock-adapter.ts'), join(output, 'tests/mock-adapter.ts'));
cpSync(join(source, 'packages/storage/storage-domain/tests/helpers/memory-backend.ts'), join(output, 'tests/memory-backend.ts'));
cpSync(join(source, 'packages/subagent/subagent/tests/working-directory-fixture.ts'), join(output, 'tests/working-directory-fixture.ts'));
const serviceTest = readFileSync(join(source, 'packages/subagent/subagent/tests/service.spec.ts'), 'utf8')
  .replace("} from '@deepseek-ai/dsh-subagent'", "} from '../subagents/index.ts'")
  .replace('const subagents = ctx.subagents', 'const subagents = ctx.subagents as unknown as SubagentRuntime');
writeFileSync(join(output, 'tests/upstream-subagents-service.spec.ts'), serviceTest);
const peerTests = join(source, 'packages/subagent/subagent/tests');
const nativePeers = process.env.DSH_REPLACEMENTS_NATIVE_PEERS;
const extraSuites = ['assistant-output', 'catalog', 'child-agent', 'continuation-messages', 'external-activation', 'external-lifecycle', 'run-settlement', 'timing-projection',
  ...(nativePeers === undefined ? [] : ['activation-policy', 'activation-presets', 'archive-admission', 'continuation', 'continuation-inheritance', 'control', 'list-children', 'out-of-process', 'parent-result', 'parked-wait', 'schedule-tools', 'structured', 'working-directory'])];
mkdirSync(join(output, 'tests/upstream'), { recursive: true });
cpSync(join(peerTests, 'fixtures'), join(output, 'tests/upstream/fixtures'), { recursive: true });
for (const file of readdirSync(peerTests).filter(name => name.endsWith('.ts') && (!name.endsWith('.spec.ts') || extraSuites.includes(name.replace('.spec.ts', ''))))) {
  const original = join(peerTests, file);
  let text = readFileSync(original, 'utf8').replaceAll("from '../src/", "from '../../subagents/");
  text = text.replaceAll(/from '(\.\.\/\.\.\/\.\.\/[^']+)'/g, (_match, path) => `from '${resolve(peerTests, path)}'`);
  if (file === 'manager-internals.ts') text = text.replace('return manager', 'return manager as unknown as SubagentManager');
  text = text.replaceAll("from '@deepseek-ai/dsh-subagent'", "from '../../subagents/index.ts'");
  if (file === 'control.spec.ts') text = text.replace('subagents: ctx.subagents', 'subagents: ctx.subagents as unknown as SubagentRuntime');
  if (file === 'structured.spec.ts') text = text.replace("from '../../subagents/internal.ts'", "from '@deepseek-ai/dsh-subagent/internal'");
  if (file === 'continuation.spec.ts') text = "import type {} from '@deepseek-ai/dsh-tool-jobs'\nimport type {} from '@deepseek-ai/dsh-cordis-host-runner'\n" + text;
  writeFileSync(join(output, 'tests/upstream', file), text);
}
const config = { compilerOptions, include: ['workflow/**/*.ts', 'schedule/**/*.ts', 'subagents/**/*.ts', 'acp/**/*.ts', 'tests/**/*.ts'], exclude: ['schedule/client.ts', 'subagents/client.ts'] };
writeFileSync(join(output, 'tsconfig.json'), JSON.stringify(config, null, 2));
const runtimePaths = { ...paths };
if (nativePeers !== undefined) {
  runtimePaths['@deepseek-ai/node-addon-system/flock'] = [join(nativePeers, '@deepseek-ai/node-addon-system/lib/flock.js')];
  runtimePaths['@deepseek-ai/node-addon-system/landlock-run'] = [join(nativePeers, '@deepseek-ai/node-addon-system/lib/index.js')];
}
const aliases = Object.entries(runtimePaths).filter(([name]) => !name.includes('*')).map(([name, values]) => ({ find: name, replacement: values[0] })).sort((a, b) => b.find.length - a.find.length);
writeFileSync(join(output, 'vitest.config.mjs'), `import { defineConfig } from 'vitest/config';\nimport ts from 'typescript';\nexport default defineConfig({resolve:{alias:${JSON.stringify(aliases)}},plugins:[{name:'standard-decorators',transform(code,id){if(!/\\.[cm]?tsx?$/.test(id)||!/^\\s*@/m.test(code))return;return {code:ts.transpileModule(code,{fileName:id,compilerOptions:{target:ts.ScriptTarget.ES2024,module:ts.ModuleKind.ESNext}}).outputText,map:null}}}],test:{include:['tests/**/*.spec.ts'],pool:'forks',maxWorkers:1,testTimeout:10000}});\n`);
checkOwned(ts, output, config);
run(process.execPath, [join(dependencySource, 'node_modules/vitest/vitest.mjs'), 'run', '--config', join(output, 'vitest.config.mjs')]);
