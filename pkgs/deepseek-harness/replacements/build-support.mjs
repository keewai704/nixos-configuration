import { mkdirSync, readdirSync, symlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

export function resolution(ts, source, dependencySource, output) {
  const base = ts.readConfigFile(join(source, 'tsconfig.base.json'), ts.sys.readFile).config.compilerOptions;
  const paths = Object.fromEntries(Object.entries(base.paths).map(([name, values]) => [name, values.map(value => resolve(source, value))]));
  const dependencies = new Map();
  const roots = [dependencySource, ...['packages', 'vendor'].flatMap(folder => {
    const root = join(dependencySource, folder);
    return readdirSync(root, { withFileTypes: true }).filter(entry => entry.isDirectory()).flatMap(entry => {
      const full = join(root, entry.name);
      if (folder === 'vendor') return [full];
      return readdirSync(full, { withFileTypes: true }).filter(child => child.isDirectory()).map(child => join(full, child.name));
    });
  })];
  for (const root of roots) {
    let entries;
    try { entries = readdirSync(join(root, 'node_modules'), { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      const names = entry.name.startsWith('@') ? readdirSync(join(root, 'node_modules', entry.name)).map(name => `${entry.name}/${name}`) : [entry.name];
      for (const name of names) if (!name.startsWith('@deepseek-ai/') && !dependencies.has(name)) dependencies.set(name, join(root, 'node_modules', name));
    }
  }
  mkdirSync(join(output, 'node_modules'), { recursive: true });
  for (const [name, target] of dependencies) {
    mkdirSync(dirname(join(output, 'node_modules', name)), { recursive: true });
    symlinkSync(target, join(output, 'node_modules', name));
    if (name !== 'typescript') paths[name] = [target];
  }
  return { ...base, composite: false, incremental: false, declaration: false, declarationMap: false, sourceMap: false,
    noEmit: true, paths, typeRoots: [join(dependencySource, 'node_modules/@types')] };
}

export function checkOwned(ts, output, config) {
  const parsed = ts.parseJsonConfigFileContent(config, ts.sys, output);
  const program = ts.createProgram(parsed.fileNames, parsed.options);
  const owned = program.getSourceFiles().filter(file => file.fileName.startsWith(`${output}/`) && !file.fileName.includes('/node_modules/'));
  const diagnostics = [...program.getOptionsDiagnostics(), ...owned.flatMap(file => [...program.getSyntacticDiagnostics(file), ...program.getSemanticDiagnostics(file)])];
  if (diagnostics.length) {
    console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, { getCanonicalFileName: name => name, getCurrentDirectory: () => output, getNewLine: () => '\n' }));
    throw new Error('Strict pinned-source provider/fixture typecheck failed');
  }
  console.log(`Strict pinned-source typecheck passed for ${owned.length} provider and fixture files`);
  return { parsed, program, owned };
}
