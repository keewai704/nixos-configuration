import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { resolution, checkOwned } from './build-support.mjs';
import { prepareAcp } from './acp/prepare.mjs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const [sourceArg, kernelArg, depsArg, outputArg, mode = 'build'] = process.argv.slice(2);
if (![sourceArg, kernelArg, depsArg, outputArg].every(value => value && isAbsolute(value))) {
  throw new Error('Usage: node build.mjs SOURCE KERNEL DEPS OUTPUT [prepare|build]');
}
const source = resolve(sourceArg);
const kernel = resolve(kernelArg);
const deps = resolve(depsArg);
const output = resolve(outputArg);
if (output === source || output.startsWith(`${source}/`) || output === kernel || output.startsWith(`${kernel}/`)) {
  throw new Error('Replacement package must be built outside both upstream roots');
}
if (existsSync(output)) throw new Error('Build output must not exist');
mkdirSync(output, { recursive: true });
for (const [name, path] of [['workflow', 'packages/workflow/workflow-ptc'], ['schedule', 'packages/schedule/schedule'], ['subagents', 'packages/subagent/subagent']]) {
  cpSync(join(source, path, 'src'), join(output, name), { recursive: true });
  chmodSync(join(output, name), 0o755);
  for (const file of readdirSync(join(output, name))) chmodSync(join(output, name, file), 0o644);
  const patched = spawnSync('patch', ['-p1', '--batch', '-i', join(here, `${name}.patch`)], { cwd: output, stdio: 'inherit' });
  if (patched.status !== 0) throw new Error(`${name} source patch failed`);
}
prepareAcp(source, output);
cpSync(join(here, 'journal.ts'), join(output, 'workflow/journal.ts'));
cpSync(join(here, 'budget-deadline.ts'), join(output, 'workflow/budget-deadline.ts'));
cpSync(join(here, 'schedule-admission.ts'), join(output, 'schedule/admission.ts'));
cpSync(join(here, 'outbox.ts'), join(output, 'schedule/outbox.ts'));
cpSync(join(here, 'schedule-runtime.ts'), join(output, 'schedule/runtime.ts'));
cpSync(join(here, 'schedule-recovery.ts'), join(output, 'schedule/recovery.ts'));
cpSync(join(here, 'package.json'), join(output, 'package.json'));
cpSync(join(source, 'LICENSE'), join(output, 'LICENSE'));
if (mode === 'prepare') process.exit(0);
if (mode !== 'build') throw new Error(`Unknown build mode: ${mode}`);
const ts = (await import(pathToFileURL(join(deps, 'typescript/lib/typescript.js')).href)).default;
const compilerOptions = resolution(ts, source, kernel, output);
const sdk = compilerOptions.paths['@agentclientprotocol/sdk']?.[0];
if (sdk === undefined) throw new Error('Pinned ACP SDK dependency is unavailable');
const sdkManifest = JSON.parse(readFileSync(join(sdk, 'package.json'), 'utf8'));
if (sdkManifest.name !== '@agentclientprotocol/sdk' || sdkManifest.version !== '1.4.0' || sdkManifest.license !== 'Apache-2.0') {
  throw new Error('Unexpected ACP SDK bundle input');
}
mkdirSync(join(output, 'lib/licenses'), { recursive: true });
cpSync(join(sdk, 'LICENSE'), join(output, 'lib/licenses/agentclientprotocol-sdk-LICENSE'));
writeFileSync(join(output, 'lib/licenses/agentclientprotocol-sdk.json'), JSON.stringify({
  name: sdkManifest.name, version: sdkManifest.version, license: sdkManifest.license,
  author: sdkManifest.author, repository: sdkManifest.repository,
}, null, 2) + '\n');
cpSync(join(sdk, 'dist'), join(output, 'lib/types/vendor/agentclientprotocol-sdk'), { recursive: true,
  filter: path => !path.includes('/dist/') || path.endsWith('.d.ts') || !path.split('/').at(-1).includes('.'),
});
const { parsed, owned } = checkOwned(ts, output, { compilerOptions,
  include: ['workflow/**/*.ts', 'schedule/**/*.ts', 'subagents/**/*.ts', 'acp/**/*.ts'], exclude: ['schedule/client.ts', 'subagents/client.ts'] });
const emission = ts.createProgram(owned.map(file => file.fileName), { ...parsed.options,
  noEmit: false, declaration: true, emitDeclarationOnly: true, rootDir: undefined, outDir: undefined,
});
for (const file of owned) {
  const local = relative(output, file.fileName);
  const target = join(output, 'lib/types', local.replace(/\.ts$/, '.js'));
  mkdirSync(dirname(target), { recursive: true });
  const emitted = ts.transpileModule(file.text, { fileName: file.fileName, compilerOptions: {
    target: ts.ScriptTarget.ES2024, module: ts.ModuleKind.ESNext, rewriteRelativeImportExtensions: true,
  } });
  writeFileSync(target, emitted.outputText);
  const result = emission.emit(emission.getSourceFile(file.fileName), (_name, text) => {
    const declaration = text.replaceAll("from '@agentclientprotocol/sdk'", "from '../vendor/agentclientprotocol-sdk/acp.js'");
    writeFileSync(target.replace(/\.js$/, '.d.ts'), declaration);
  }, undefined, true);
  if (result.emitSkipped || result.diagnostics.length) throw new Error(`Declaration emission failed: ${local}`);
}
const { build } = await import(pathToFileURL(join(deps, 'tsdown/dist/index.mjs')).href);
await build({
  cwd: output, config: false,
  entry: {
    ...Object.fromEntries(['workflow', 'schedule', 'subagents', 'acp'].map(name => [name, join(output, `lib/types/${name}/index.js`)])),
    approval: join(output, 'lib/types/acp/approval.js'),
    'approval-journal': join(output, 'lib/types/acp/approval-journal-plugin.js'),
  },
  outDir: join(output, 'lib'), format: ['esm'], platform: 'node', target: 'es2024', dts: false,
  clean: false, fixedExtension: false, deps: {
    neverBundle: [/^@deepseek-ai\//, /^@js-temporal\//, /^zod(?:\/|$)/],
    alwaysBundle: ['@agentclientprotocol/sdk'], onlyBundle: ['@agentclientprotocol/sdk'],
  },
});
writeFileSync(join(output, 'build-inputs.json'), JSON.stringify({ source, kernel, typesChecked: true }, null, 2) + '\n');
