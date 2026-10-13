import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { prepareAcp } from './prepare.mjs';

const [source, runtime, tools, sdk] = process.argv.slice(2);
if (![source, runtime, tools, sdk].every(value => value && isAbsolute(value))) throw new Error('Usage: node verify.mjs PINNED_SOURCE RUNTIME_NODE_MODULES BUILD_NODE_MODULES ACP_SDK');
const output = mkdtempSync(join(tmpdir(), 'dsh-acp-verify-'));
prepareAcp(source, output);
mkdirSync(join(output, 'node_modules/@agentclientprotocol'), { recursive: true });
symlinkSync(join(runtime, '@deepseek-ai'), join(output, 'node_modules/@deepseek-ai'));
symlinkSync(sdk, join(output, 'node_modules/@agentclientprotocol/sdk'));
writeFileSync(join(output, 'package.json'), JSON.stringify({ type: 'module' }));
const ts = (await import(pathToFileURL(join(tools, 'typescript/lib/typescript.js')).href)).default;
const options = {
  target: ts.ScriptTarget.ES2024, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
  strict: true, exactOptionalPropertyTypes: true, noUncheckedIndexedAccess: true, noImplicitOverride: true,
  noUnusedLocals: true, noUnusedParameters: true, skipLibCheck: true, declaration: true,
  rewriteRelativeImportExtensions: true, rootDir: output, outDir: join(output, 'lib'),
  types: ['node'], typeRoots: [join(tools, '@types')],
};
const program = ts.createProgram(ts.sys.readDirectory(join(output, 'acp'), ['.ts']), options);
const diagnostics = ts.getPreEmitDiagnostics(program);
if (diagnostics.length) {
  console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, { getCanonicalFileName: name => name, getCurrentDirectory: () => output, getNewLine: () => '\n' }));
  process.exit(1);
}
if (program.emit().emitSkipped) throw new Error('ACP TypeScript emission failed');
const test = spawnSync(process.execPath, ['--test', '--test-timeout=10000', join(dirname(fileURLToPath(import.meta.url)), 'approval.test.mjs')], {
  stdio: 'inherit', env: { ...process.env, ACP_TEST_BUILD: output },
});
console.log(`ACP verification output: ${resolve(output)}`);
if (test.status !== 0) process.exit(test.status ?? 1);
