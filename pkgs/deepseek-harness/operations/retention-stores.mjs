import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { scanOperationDatabase } from './retention-sqlite.mjs';
import { codeVersions } from './retention-code-policy.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const ensure = (condition, message) => { if (!condition) throw new Error(message); };
const packageName = /^(?:@[a-z0-9._-]+\/)?[a-z0-9._-]+$/i;
const storePath = /^\/nix\/store\/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/]+(?:\/.*)?$/;
const textFiles = /\.(?:json|jsonl|yaml|yml|log|txt|md)$/;
const migrationJson = /^(?:operations\/migrations\/[a-f0-9]{64}\/(?:source\.bin|\d{6}\.stage|\.manifest\.json-[a-f0-9]{16}\.tmp)|operations\/migrations\/\.active\.json-[a-f0-9]{16}\.tmp)$/;
const profileFiles = new Set(['package.json', 'cordis.yml', 'cordis.patch.yml', 'settings.yaml', 'settings.yaml.imported', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', '.nix-managed']);
const backendNames = new Map([
  ['session-persistence-jsonl', '@deepseek-ai/dsh-session-persistence-jsonl'],
  ['attachment-local', '@deepseek-ai/dsh-attachment-local'],
  ['storage', '@deepseek-ai/dsh-storage'],
  ['storage-json', '@deepseek-ai/dsh-storage-json'],
  ['storage-domain', '@deepseek-ai/dsh-storage-domain'],
  ['session-query-sqlite', '@deepseek-ai/dsh-session-query-sqlite'],
  ['session-projection-cache', '@deepseek-ai/dsh-session-projection-cache'],
]);
class Expression { constructor(value) { this.source = value; this.retentionExpression = true; } }

export function collectDigests(value, refs) {
  for (const match of value.matchAll(/[a-f0-9]{64,}/gi)) {
    ensure(match[0].length <= 100_000, 'Digest reference scan bound exceeded');
    for (let offset = 0; offset <= match[0].length - 64; offset++) {
      refs.add(match[0].slice(offset, offset + 64).toLowerCase());
      ensure(refs.size <= 100_000, 'Digest reference count bound exceeded');
    }
  }
}

export function scanAuxiliary(tree, rootNames, refs, { collect, parseJson, hash, identity, catalogPath, nodeModules, gc }) {
  const require = createRequire(catalogPath);
  const yaml = require('yaml');
  const { applyEntryPatches } = require('@deepseek-ai/cordis-plugin-include');
  const audit = { scanned: [], immutableCode: [], unscanned: [] };
  const packages = new Map();
  const codeKey = (relative, name) => `${relative}:${name}`;
  const parsed = new Map();
  const raw = data => {
    const text = data.toString('latin1');
    collectDigests(text, refs);
    collectDigests(text.replace(/\\u00([0-9a-f]{2})/gi, (_, hex) => String.fromCharCode(Number.parseInt(hex, 16))), refs);
  };
  const decode = (data, label) => {
    try { return new TextDecoder('utf-8', { fatal: true }).decode(data); }
    catch { throw new Error(`Malformed UTF-8 auxiliary state: ${label}`); }
  };
  const parse = (data, label) => {
    raw(data);
    const text = decode(data, label);
    let value;
    if (label.endsWith('.json') || migrationJson.test(label) || /^operations\/approvals\/[a-f0-9]{64}\.[a-f0-9-]{36}\.tmp$/.test(label)) value = parseJson(data, label);
    else if (/\.jsonl$/.test(label)) {
      ensure(text === '' || text.endsWith('\n'), `Incomplete auxiliary JSONL: ${label}`);
      value = text.trim() ? text.trimEnd().split('\n').map(line => parseJson(Buffer.from(line), label)) : [];
    } else if (/\.(?:ya?ml|yaml\.imported)$/.test(label)) {
      const doc = yaml.parseDocument(text, { customTags: [{ tag: 'tag:yaml.org,2002:js', resolve: value => new Expression(value) }], uniqueKeys: true, strict: true });
      ensure(doc.errors.length === 0 && doc.warnings.length === 0, `Malformed or unsupported YAML: ${label}`);
      try { value = doc.toJS({ maxAliasCount: 100 }); }
      catch { throw new Error(`Unsupported YAML aliases: ${label}`); }
      if (gc && !storePath.test(label)) {
        const visit = (item, depth = 0, seen = new Set()) => {
          ensure(depth <= 100 && !seen.has(item), `Reference nesting or alias cycle exceeds scan bounds: ${label}`);
          if (item instanceof Expression) ensure(["dshHomePath('sessions')", "dshHomePath('storages')"].includes(item.source), `Dynamic configuration expression requires retention review: ${label}`);
          else if (item && typeof item === 'object') {
            seen.add(item);
            for (const child of Object.values(item)) visit(child, depth + 1, seen);
            seen.delete(item);
          }
        };
        visit(value);
      }
    } else {
      ensure(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text), `Unknown binary auxiliary store: ${label}`);
      value = text;
    }
    const reserved = (item, depth = 0, seen = new Set()) => {
      ensure(depth <= 100 && !seen.has(item), `Reference nesting or alias cycle exceeds scan bounds: ${label}`);
      if (!item || typeof item !== 'object' || item instanceof Expression) return;
      ensure(!Object.hasOwn(item, 'retentionExpression'), `Reserved configuration expression marker: ${label}`);
      seen.add(item);
      for (const child of Object.values(item)) reserved(child, depth + 1, seen);
      seen.delete(item);
    };
    reserved(value);
    collect(value, refs, label);
    return value;
  };
  const read = relative => {
    const { data } = tree.read(relative);
    const value = parse(data, relative);
    audit.scanned.push({ path: relative, bytes: data.length, sha256: hash(data) });
    parsed.set(relative, value);
    return value;
  };
  const storeAnchor = fs.lstatSync('/nix/store', { bigint: true });
  const nixAnchor = fs.lstatSync('/nix', { bigint: true });
  const protectedStore = (storeAnchor.mode & 0o022n) === 0n || ((storeAnchor.mode & 0o002n) === 0n && (storeAnchor.mode & 0o1000n) !== 0n);
  ensure(storeAnchor.isDirectory() && nixAnchor.isDirectory() && protectedStore && (nixAnchor.mode & 0o022n) === 0n, 'Unsafe immutable code anchor');
  const storeOwner = storeAnchor.uid;
  const immutable = absolute => {
    ensure(storePath.test(absolute) && path.resolve(absolute) === absolute, `Code root is not an exact Nix store path: ${absolute}`);
    const target = fs.realpathSync(absolute);
    ensure(storePath.test(target), `Code root escapes immutable Nix storage: ${absolute}`);
    for (let current = target; current !== '/nix/store'; current = path.dirname(current)) {
      const stat = fs.lstatSync(current, { bigint: true });
      ensure(!stat.isSymbolicLink() && stat.uid === storeOwner && (stat.mode & 0o222n) === 0n && (stat.isDirectory() || stat.isFile()), `Code root is not immutable: ${absolute}`);
    }
    return target;
  };
  const checkedCode = new Set();
  const codeTree = (absolute, depth = 0) => {
    ensure(depth <= 64, 'Immutable code nesting bound exceeded');
    const target = immutable(absolute);
    if (checkedCode.has(target)) return;
    ensure(checkedCode.size < 100_000, 'Immutable code entry limit exceeded');
    checkedCode.add(target);
    if (fs.lstatSync(target).isDirectory()) {
      const names = fs.readdirSync(target).sort();
      ensure(names.length <= 100_000, 'Immutable code entry limit exceeded');
      for (const name of names) codeTree(`${target}/${name}`, depth + 1);
    }
  };
  const externalRead = absolute => {
    const target = immutable(absolute);
    const stat = fs.lstatSync(target, { bigint: true });
    ensure(stat.isFile() && stat.size <= 16n * 1024n * 1024n, `Unknown or oversized code metadata: ${absolute}`);
    const fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    let data;
    try { data = fs.readFileSync(fd); } finally { fs.closeSync(fd); }
    tree.total += data.length;
    ensure(tree.total <= 1024 * 1024 * 1024, 'Total scan byte limit exceeded');
    ensure(audit.scanned.length < 100_000, 'Auxiliary entry limit exceeded');
    audit.scanned.push({ path: absolute, target, bytes: data.length, sha256: hash(data) });
    return parse(data, absolute);
  };
  const codePackage = (absolute, name) => {
    ensure(packageName.test(name), `Unknown code package name: ${name}`);
    const target = immutable(absolute);
    const suffix = `/node_modules/${name}`;
    const composed = new RegExp(`^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-dsh-node-modules/${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`);
    ensure((target.endsWith(suffix) && /\/lib\/(?:deepseek-harness\/)?node_modules\//.test(target)) || composed.test(target), `Unrecognized immutable code-root semantics: ${absolute}`);
    codeTree(target);
    const manifest = externalRead(`${target}/package.json`);
    ensure(object(manifest) && manifest.name === name && typeof manifest.version === 'string', `Code package identity mismatch: ${absolute}`);
    return { target, manifest };
  };
  const moduleDirectory = relative => {
    const stat = tree.stat(relative, true);
    if (stat.isSymbolicLink()) {
      const target = immutable(fs.realpathSync(tree.absolute(relative)));
      ensure(/^\/nix\/store\/[0-9abcdfghijklmnpqrsvwxyz]{32}-(?:dsh-node-modules|[^/]+\/lib\/(?:deepseek-harness\/)?node_modules)$/.test(target), `Unrecognized immutable module-root semantics: ${relative}`);
      const entry = tree.observe(relative, stat);
      entry.codeTarget = target;
      entry.link = fs.readlinkSync(tree.absolute(relative));
      const names = fs.readdirSync(target).sort();
      ensure(names.length <= 100_000, 'Code entry limit exceeded');
      for (const name of names) {
        if (name === '.bin') { codeTree(`${target}/.bin`); continue; }
        const children = name.startsWith('@') ? fs.readdirSync(immutable(`${target}/${name}`)).sort().map(leaf => `${name}/${leaf}`) : [name];
        ensure(children.length <= 100_000, 'Code entry limit exceeded');
        for (const child of children) packages.set(codeKey(relative, child), codePackage(`${target}/${child}`, child));
      }
      audit.immutableCode.push({ path: relative, target, packages: names });
      return;
    }
    for (const name of tree.directory(relative)) {
      if (name.startsWith('@')) {
        ensure(/^@[a-z0-9._-]+$/i.test(name), `Unknown module scope: ${relative}/${name}`);
        for (const leaf of tree.directory(`${relative}/${name}`)) link(`${relative}/${name}/${leaf}`, `${name}/${leaf}`);
      } else link(`${relative}/${name}`, name);
    }
  };
  const link = (relative, name) => {
    const stat = tree.stat(relative, true);
    ensure(stat.isSymbolicLink(), `Only immutable Nix code links are supported in module roots: ${relative}`);
    const packageInfo = codePackage(fs.realpathSync(tree.absolute(relative)), name);
    const codeTarget = packageInfo.target;
    packages.set(codeKey(relative.slice(0, -name.length - 1), name), packageInfo);
    const entry = tree.observe(relative, stat);
    entry.codeTarget = codeTarget;
    entry.link = fs.readlinkSync(tree.absolute(relative));
    ensure(JSON.stringify(identity(tree.stat(relative, true))) === JSON.stringify(identity(stat)), `Code link changed during scan: ${relative}`);
    audit.immutableCode.push({ path: relative, target: codeTarget, package: name });
  };
  const trustedPackages = new Map();
  const trustPackage = name => {
    ensure(codeVersions.has(name), `Unknown plugin package requires retention review: ${name}`);
    if (trustedPackages.has(name)) return trustedPackages.get(name);
    let root = path.resolve(path.dirname(catalogPath), '../../..');
    if (nodeModules) {
      root = immutable(nodeModules);
      ensure(/^\/nix\/store\/[0-9abcdfghijklmnpqrsvwxyz]{32}-dsh-node-modules$/.test(root), 'Unknown composed DSH code anchor');
    }
    const info = codePackage(path.join(root, name), name);
    ensure(info.manifest.version === codeVersions.get(name), `Unsupported pinned plugin version: ${name}`);
    trustedPackages.set(name, info);
    return info;
  };
  const plugin = (name, pinnedLayer) => {
    if (name === 'cordis:group') return;
    const match = /^(?:@[a-z0-9._-]+\/[a-z0-9._-]+|[a-z0-9._-]+)(?=\/|$)/i.exec(name);
    ensure(match, `Unknown plugin module specifier: ${name}`);
    ensure(codeVersions.has(match[0]), `Unknown plugin package requires retention review: ${name}`);
    if (pinnedLayer) return;
    const info = trustPackage(match[0]);
    const exported = name.length === match[0].length ? '.' : `.${name.slice(match[0].length)}`;
    ensure(exported === '.' ? info.manifest.main || info.manifest.exports : object(info.manifest.exports) && Object.hasOwn(info.manifest.exports, exported), `Unknown plugin entrypoint: ${name}`);
  };
  const composedLabels = new Set();
  const backend = (value, label, depth = 0, entry = false) => {
    ensure(depth <= 100, `Configuration nesting bound exceeded: ${label}`);
    if (Array.isArray(value)) {
      if (depth === 0) ensure(!value.some(row => row instanceof Expression), `Dynamic configuration rows cannot be audited: ${label}`);
      for (const row of value) backend(row, label, depth + 1, entry || depth === 0);
      return;
    }
    if (!object(value) || value instanceof Expression) return;
    const id = typeof value.id === 'string' ? value.id : '';
    const name = typeof value.name === 'string' ? value.name : '';
    const knownId = [...backendNames].find(([key, plugin]) => id === key || name === plugin)?.[0];
    if (gc && name && entry) plugin(name, storePath.test(label) || composedLabels.has(label));
    ensure(!(value.name instanceof Expression) && !(value.id instanceof Expression), `Dynamic plugin identity cannot be audited: ${label}`);
    const staticComposition = item => !(item instanceof Expression) && !(Array.isArray(item) && item.some(row => row instanceof Expression));
    for (const key of ['insert', 'plugins', 'include', 'imports', 'patches']) ensure(staticComposition(value[key]), `Dynamic configuration composition cannot be audited: ${label}`);
    if (id || name || Object.hasOwn(value, 'group')) ensure(staticComposition(value.config), `Dynamic plugin configuration cannot be audited: ${label}`);
    ensure(!/(?:cordis-plugin-include|^cordis:include$)/.test(name), `External configuration include cannot be audited: ${label}`);
    const sensitive = knownId || /(?:persistence|attachment-(?:local|store)|storage|session-query)/i.test(`${id} ${name}`);
    if (sensitive) {
      ensure(knownId && (!name || name === backendNames.get(knownId)), `Unknown active custom backend: ${label}`);
      const config = value.config ?? {};
      ensure(object(config) && !(config instanceof Expression), `Unknown backend configuration: ${label}`);
      const fields = {
        'session-persistence-jsonl': ['root', 'compression'],
        'attachment-local': ['dshHome', 'maxImageBytes', 'maxImagesPerMessage', 'maxMessageImageBytes', 'maxImagePixels', 'maxImageDimension', 'normalizedImageMaxPixels', 'normalizedImageMaxDimension', 'normalizedImageMaxBytes', 'imageCompressionConcurrency'],
        storage: [],
        'storage-json': ['root'],
        'storage-domain': ['backend'],
        'session-query-sqlite': ['path', 'openAt'],
        'session-projection-cache': ['writeEveryEvents', 'writeIntervalMs'],
      };
      ensure(Object.keys(config).every(key => fields[knownId].includes(key)), `Unknown backend configuration field: ${label}`);
      const expectedRoot = knownId === 'session-persistence-jsonl' ? 'sessions' : knownId === 'storage-json' ? 'storages' : null;
      if (expectedRoot && Object.hasOwn(config, 'root')) {
        const root = config.root;
        ensure(root === path.join(tree.home, expectedRoot) || (root instanceof Expression && root.source === `dshHomePath('${expectedRoot}')`), `External or dynamic backend root: ${label}`);
      }
      if (knownId === 'attachment-local' && Object.hasOwn(config, 'dshHome')) ensure(config.dshHome === tree.home, `External or dynamic attachment backend: ${label}`);
      if (knownId === 'storage-domain') ensure(config.backend === undefined || config.backend === 'json', `Unknown active custom backend: ${label}`);
      if (knownId === 'session-query-sqlite') ensure(config.openAt === 'never' && (config.path === undefined || config.path === ':memory:'), `Active custom query backend requires manual retention: ${label}`);
    }
    for (const [key, item] of Object.entries(value)) {
      if (backendNames.has(key)) backend({ id: key, config: item }, label, depth + 1);
      else backend(item, label, depth + 1, ['insert', 'plugins', 'patches'].includes(key) || (key === 'config' && (value.group === true || ['cordis:group', '@deepseek-ai/cordis-plugin-group'].includes(name))));
    }
  };
  const unknown = relative => {
    ensure(!gc, `Unrecognized or unscanned auxiliary stores: ${relative}`);
    audit.unscanned.push(relative);
  };
  const walkText = (relative, depth = 0) => {
    ensure(depth <= 32, `Auxiliary directory nesting bound exceeded: ${relative}`);
    for (const name of tree.directory(relative)) {
      const child = `${relative}/${name}`;
      ensure(child !== 'operations/migrations/active.json', 'Unfinished storage migration; retention is blocked until migration recovery completes');
      const stat = tree.stat(child);
      if (stat.isDirectory()) walkText(child, depth + 1);
      else if (child.endsWith('.sqlite')) {
        const database = scanOperationDatabase(tree, child, refs, { collect, parseJson, hash, raw });
        if (database) audit.scanned.push(database);
        else unknown(child);
      } else if (textFiles.test(name) || migrationJson.test(child) || /^operations\/approvals\/[a-f0-9]{64}\.[a-f0-9-]{36}\.tmp$/.test(child)) read(child);
      else if (name.endsWith('.lock')) {
        ensure(tree.read(child).data.length === 0, `Unrecognized nonempty auxiliary lock: ${child}`);
      } else unknown(child);
    }
  };
  const cache = () => {
    const walk = (relative, depth = 0) => {
      ensure(depth <= 32, `Cache nesting bound exceeded: ${relative}`);
      for (const name of tree.directory(relative)) {
        const child = `${relative}/${name}`;
        const stat = tree.stat(child);
        if (stat.isDirectory()) walk(child, depth + 1);
        else if (/^cache\/attachments\/request-images\/([a-f0-9]{2})\/([a-f0-9]{64})$/.test(child)) {
          const [, shard, digest] = /^cache\/attachments\/request-images\/([a-f0-9]{2})\/([a-f0-9]{64})$/.exec(child);
          ensure(digest.startsWith(shard), `Invalid request-image cache shard: ${child}`);
          const { data } = tree.read(child);
          ensure(data.subarray(0, 3).equals(Buffer.from([255, 216, 255])) || data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) || (data.toString('ascii', 0, 4) === 'RIFF' && data.toString('ascii', 8, 12) === 'WEBP'), `Unknown request-image cache format: ${child}`);
          raw(data);
          refs.add(digest);
          audit.scanned.push({ path: child, bytes: data.length, sha256: hash(data) });
        } else if (textFiles.test(name)) read(child);
        else unknown(child);
      }
    };
    walk('cache');
  };
  for (const name of rootNames) {
    if (['sessions', 'attachments', 'storages'].includes(name)) continue;
    if (name === 'node_modules') { moduleDirectory(name); continue; }
    if (name === 'profiles') {
      for (const profile of tree.directory(name)) {
        const relative = `profiles/${profile}`;
        if (profile === '.nix-sync.lock') { ensure(tree.read(relative).data.length === 0, 'Nonempty Nix sync lock'); continue; }
        if (profile === 'node_modules') { moduleDirectory(relative); continue; }
        for (const file of tree.directory(relative)) {
          const child = `${relative}/${file}`;
          if (file === 'node_modules') moduleDirectory(child);
          else if (profileFiles.has(file)) read(child);
          else if (file === '.plugin-manager') walkText(child);
          else unknown(child);
        }
      }
    } else if (name === 'cache') cache();
    else if (['plugins', 'operations', 'skills', 'logs'].includes(name)) walkText(name);
    else if (name === '.operations.lock') tree.read(name);
    else read(name);
  }
  if (gc) for (const [key, info] of packages) {
    const name = key.slice(key.indexOf(':') + 1);
    const kernel = path.resolve(path.dirname(catalogPath), '../../..', name);
    let anchor = path.resolve(path.dirname(catalogPath), '../../..');
    if (nodeModules) {
      anchor = immutable(nodeModules);
      ensure(/^\/nix\/store\/[0-9abcdfghijklmnpqrsvwxyz]{32}-dsh-node-modules$/.test(anchor), 'Unknown composed DSH code anchor');
    }
    const trusted = codePackage(path.join(anchor, name), name);
    ensure([trusted.target, path.dirname(fs.realpathSync(`${trusted.target}/package.json`)), kernel].includes(info.target), `Unreviewed profile code override: ${name}`);
  }
  const profileLayers = new Map();
  const rehydrate = value => {
    if (!value || typeof value !== 'object') return value;
    if (value.retentionExpression === true) return new Expression(value.source);
    for (const key of Object.keys(value)) value[key] = rehydrate(value[key]);
    return value;
  };
  const compose = (layers, label) => {
    ensure(layers.every(Array.isArray), `Unknown profile patch list: ${label}`);
    const result = rehydrate(layers.reduce((entries, layer) => applyEntryPatches(entries, layer, () => {}), []));
    composedLabels.add(label);
    backend(result, label);
    return result;
  };
  for (const [label, value] of parsed) {
    if (/(?:cordis(?:\.patch)?\.yml|settings\.yaml(?:\.imported)?)$/.test(label)) {
      ensure(!(value instanceof Expression), `Dynamic configuration cannot be audited: ${label}`);
      backend(value, label);
    }
    if (!label.endsWith('package.json') || !object(value?.dsh?.profile)) continue;
    const layers = [];
    profileLayers.set(path.dirname(label), layers);
    const bundles = value.dsh.profile.bundles;
    ensure(Array.isArray(bundles) && bundles.every(name => typeof name === 'string' && packageName.test(name)), `Unknown profile bundle manifest: ${label}`);
    for (const name of bundles) {
      const profileRoot = `${path.dirname(label)}/node_modules`;
      let info = packages.get(codeKey(profileRoot, name)) ?? packages.get(codeKey('profiles/node_modules', name)) ?? packages.get(codeKey('node_modules', name));
      if (!info) {
        let root = path.resolve(path.dirname(catalogPath), '../../..');
        if (nodeModules) {
          root = immutable(nodeModules);
          ensure(/^\/nix\/store\/[0-9abcdfghijklmnpqrsvwxyz]{32}-dsh-node-modules$/.test(root), 'Unknown composed DSH code anchor');
        }
        info = codePackage(path.join(root, name), name);
      }
      if (gc) {
        const trusted = trustPackage(name);
        ensure([trusted.target, path.dirname(fs.realpathSync(`${trusted.target}/package.json`))].includes(info.target), `Unreviewed profile bundle override: ${name}`);
      }
      const { target, manifest } = info;
      const files = typeof manifest.dsh?.bundle?.patch === 'string' ? [manifest.dsh.bundle.patch] : manifest.dsh?.bundle?.patch;
      ensure(Array.isArray(files) && files.length > 0 && files.length <= 100, `Unknown bundle patch declaration: ${name}`);
      for (const file of files) {
        ensure(typeof file === 'string' && path.resolve(target, file).startsWith(`${target}/`) && /\.ya?ml$/.test(file), `External bundle patch: ${name}`);
        const absolute = path.resolve(target, file);
        const patches = externalRead(absolute);
        backend(patches, absolute);
        layers.push(patches);
      }
    }
  }
  for (const label of parsed.keys()) if (/^profiles\/[^/]+\/cordis\.patch\.yml$/.test(label) && !profileLayers.has(path.dirname(label))) profileLayers.set(path.dirname(label), []);
  if (!profileLayers.size) profileLayers.set('.', []);
  for (const [directory, layers] of profileLayers) {
    const local = directory === '.' ? [] : parsed.get(`${directory}/cordis.patch.yml`) ?? [];
    const home = parsed.get('cordis.patch.yml') ?? [];
    compose([...layers, local, home], `${directory}/effective-composition`);
  }
  return audit;
}
