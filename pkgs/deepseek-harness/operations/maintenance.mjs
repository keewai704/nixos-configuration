import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import * as zlib from 'node:zlib';
import { scanAuxiliary, collectDigests } from './retention-stores.mjs';
import { beginWorkspace, finishWorkspace, recoverWorkspace, pruneWorkspace, journalPath, workspacePath } from './retention-workspace.mjs';

const DAY = 86_400_000;
const MAX_FILE = 256 * 1024 * 1024;
const MAX_TOTAL = 1024 * 1024 * 1024;
const MAX_ENTRIES = 100_000;
const hash = value => createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const fail = message => { throw new Error(message); };
const ensure = (condition, message) => { if (!condition) fail(message); };
const encode = value => {
  if (value === '.') return '~002E';
  if (value === '..') return '~002E~002E';
  return value.split('').map(c => /^[A-Za-z0-9._-]$/.test(c) ? c : `~${c.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`).join('');
};
const projectKey = cwd => {
  if (cwd === undefined) return '_no-cwd';
  ensure(typeof cwd === 'string' && cwd.length > 0, 'Invalid session cwd');
  let readable = '';
  let separatorRun = false;
  for (let index = 0; index < cwd.length; index++) {
    const code = cwd.charCodeAt(index);
    const character = String.fromCharCode(code);
    if (character === '/' || character === '\\' || character === ':') {
      if (!separatorRun) readable += '-';
      separatorRun = true;
    } else if (/^[A-Za-z0-9._-]$/.test(character)) {
      readable += character;
      separatorRun = false;
    } else {
      readable += `~${code.toString(16).toUpperCase().padStart(4, '0')}`;
      separatorRun = false;
    }
  }
  const slug = readable.replace(/^-+/, '') || 'root';
  return `--${slug.slice(0, 251)}--`;
};
const timestamp = value => {
  ensure(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value), 'Timestamp requires ISO-8601 with an explicit timezone');
  const [, year, month, day, hour, minute, second, , offsetHour, offsetMinute] = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(Z|[+-](\d{2}):(\d{2}))$/.exec(value);
  const leap = Number(year) % 4 === 0 && (Number(year) % 100 !== 0 || Number(year) % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  ensure(Number(month) >= 1 && Number(month) <= 12 && Number(day) >= 1 && Number(day) <= days[Number(month) - 1] && Number(hour) < 24 && Number(minute) < 60 && Number(second) < 60 && (offsetHour === undefined || (Number(offsetHour) < 24 && Number(offsetMinute) < 60)), 'Invalid calendar timestamp');
  const time = Date.parse(value);
  ensure(Number.isSafeInteger(time) && time >= 0, 'Invalid timestamp');
  return time;
};

function options(argv) {
  const args = [...argv];
  const action = args[0] && !args[0].startsWith('--') ? args.shift() : 'preview';
  ensure(['preview', 'apply', 'recover-workspace'].includes(action), 'Expected preview, apply or recover-workspace');
  const values = { ids: [], max: 100, graceDays: 7, gc: false };
  const seen = new Set();
  const names = { '--home': 'home', '--id': 'ids', '--older-than': 'olderThan', '--max': 'max', '--attachment-grace-days': 'graceDays', '--as-of': 'asOf', '--plan-hash': 'planHash', '--confirm': 'confirm' };
  while (args.length) {
    const flag = args.shift();
    ensure(flag === '--gc-attachments' || Object.hasOwn(names, flag), `Unknown option: ${flag}`);
    ensure(flag === '--id' || !seen.has(flag), `Repeated option: ${flag}`);
    seen.add(flag);
    if (flag === '--gc-attachments') { values.gc = true; continue; }
    const value = args.shift();
    ensure(typeof value === 'string' && value.length > 0 && !value.includes('\0'), `Missing or invalid value for ${flag}`);
    if (flag === '--id') values.ids.push(value);
    else values[names[flag]] = value;
  }
  ensure(values.home && path.isAbsolute(values.home), '--home must be an explicit absolute DSH_HOME');
  values.home = path.resolve(values.home);
  ensure(values.home !== '/' && values.home !== path.parse(values.home).root, 'Refusing filesystem root');
  ensure(!(values.ids.length && values.olderThan), 'Use explicit ids OR --older-than, not both');
  ensure(new Set(values.ids).size === values.ids.length, 'Duplicate session id');
  values.ids.sort();
  for (const key of ['max', 'graceDays']) {
    ensure(/^\d+$/.test(String(values[key])), `Invalid ${key}`);
    values[key] = Number(values[key]);
  }
  ensure(values.max >= 1 && values.max <= 1000, '--max must be between 1 and 1000');
  ensure(values.graceDays >= 7 && values.graceDays <= 3650, 'Attachment grace must be 7–3650 days');
  if (values.olderThan) values.olderThan = timestamp(values.olderThan);
  if (action === 'apply') {
    ensure(values.asOf, 'apply requires --as-of from the preview');
    ensure(/^[a-f0-9]{64}$/.test(values.planHash ?? ''), 'apply requires the exact --plan-hash');
    ensure(values.confirm === `DELETE:${values.planHash}`, 'apply requires --confirm DELETE:<exact plan hash>');
  } else if (action === 'recover-workspace') {
    ensure(values.confirm === 'RECOVER-WORKSPACE' && seen.size === 2 && seen.has('--home') && seen.has('--confirm'), 'recover-workspace requires only --home and --confirm RECOVER-WORKSPACE');
  } else ensure(!values.planHash && !values.confirm, 'Confirmation is only accepted by apply');
  values.asOf = values.asOf ? timestamp(values.asOf) : Date.now();
  ensure(values.asOf <= Date.now() + 1000 && values.asOf >= Date.now() - DAY, '--as-of must be within the past 24 hours');
  ensure(!values.olderThan || values.olderThan <= values.asOf, '--older-than cannot be in the future');
  return { action, ...values };
}

function identity(stat) {
  return Object.fromEntries(['dev', 'ino', 'mode', 'uid', 'gid', 'nlink', 'size', 'mtimeNs', 'ctimeNs'].map(key => [key, String(stat[key])]));
}

class Tree {
  constructor(home) {
    this.home = home;
    this.root = this.stat('');
    ensure(this.root.isDirectory(), 'DSH_HOME must be a directory');
    ensure(fs.realpathSync(home) === home, 'DSH_HOME and its ancestors must not be symlinks');
    this.snapshot = new Map();
    this.total = 0;
  }
  absolute(relative) {
    const target = path.resolve(this.home, relative);
    ensure(relative === '' || target.startsWith(`${this.home}/`), `Path escapes DSH_HOME: ${relative}`);
    return target;
  }
  stat(relative, allowCodeLink = false) {
    const parent = path.dirname(this.absolute(relative));
    ensure(fs.realpathSync(parent) === parent, `Symlink ancestor: ${relative || 'DSH_HOME'}`);
    const uid = BigInt(process.getuid());
    for (let ancestor = parent; ; ancestor = path.dirname(ancestor)) {
      const metadata = fs.lstatSync(ancestor, { bigint: true });
      const filesystemRoot = ancestor === path.dirname(ancestor);
      ensure(metadata.isDirectory() && (filesystemRoot || metadata.uid === 0n || metadata.uid === uid), `Unsafe ancestor ownership: ${ancestor}`);
      ensure((metadata.mode & 0o022n) === 0n || (!filesystemRoot && metadata.uid === 0n && (metadata.mode & 0o1000n) !== 0n), `Unsafe ancestor writable permissions: ${ancestor}`);
      if (filesystemRoot) break;
    }
    const stat = fs.lstatSync(this.absolute(relative), { bigint: true });
    const codeLink = allowCodeLink && stat.isSymbolicLink();
    ensure(codeLink || (!stat.isSymbolicLink() && (stat.isFile() || stat.isDirectory())), `Unsafe file type or symlink: ${relative || 'DSH_HOME'}`);
    ensure(stat.uid === BigInt(process.getuid()) && (codeLink || (stat.mode & 0o022n) === 0n), `Unsafe ownership or writable permissions: ${relative || 'DSH_HOME'}`);
    if (this.root) ensure(stat.dev === this.root.dev, `Cross-device storage is unsupported: ${relative}`);
    return stat;
  }
  observe(relative, stat) {
    ensure(this.snapshot.has(relative) || this.snapshot.size < MAX_ENTRIES, 'Storage entry limit exceeded');
    const entry = { ...identity(stat) };
    this.snapshot.set(relative, entry);
    return entry;
  }
  directory(relative) {
    const stat = this.stat(relative);
    ensure(stat.isDirectory(), `Expected directory: ${relative}`);
    const previous = this.snapshot.get(relative);
    if (previous) ensure(Object.entries(identity(stat)).every(([key, value]) => previous[key] === value), `Directory changed during scan: ${relative}`);
    const entry = this.observe(relative, stat);
    const children = fs.readdirSync(this.absolute(relative)).sort();
    ensure(children.length <= MAX_ENTRIES, 'Storage entry limit exceeded');
    entry.children = children;
    ensure(JSON.stringify(identity(this.stat(relative))) === JSON.stringify(identity(stat)), `Directory changed during scan: ${relative}`);
    return children;
  }
  read(relative, allowLinks = false) {
    const before = this.stat(relative);
    ensure(before.isFile(), `Expected regular file: ${relative}`);
    ensure(allowLinks || before.nlink === 1n, `Unexpected hardlink: ${relative}`);
    ensure(before.size <= BigInt(MAX_FILE), `File exceeds scan bound: ${relative}`);
    const fd = fs.openSync(this.absolute(relative), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK | fs.constants.O_NOATIME);
    try {
      ensure(JSON.stringify(identity(fs.fstatSync(fd, { bigint: true }))) === JSON.stringify(identity(before)), `File changed while opening: ${relative}`);
      const data = fs.readFileSync(fd);
      this.total += data.length;
      ensure(this.total <= MAX_TOTAL, 'Total scan byte limit exceeded');
      ensure(JSON.stringify(identity(this.stat(relative))) === JSON.stringify(identity(before)), `File changed during scan: ${relative}`);
      const entry = this.observe(relative, before);
      entry.sha256 = hash(data);
      return { data, stat: before, entry };
    } finally { fs.closeSync(fd); }
  }
  assertUnchanged(relative, expected) {
    ensure(fs.realpathSync(path.dirname(this.absolute(relative))) === path.dirname(this.absolute(relative)), `Ancestor changed: ${relative}`);
    const current = identity(this.stat(relative, Boolean(expected.codeTarget)));
    ensure(Object.keys(current).every(key => current[key] === expected[key]), `Storage changed after planning: ${relative}`);
    if (expected.codeTarget) ensure(fs.realpathSync(this.absolute(relative)) === expected.codeTarget && fs.readlinkSync(this.absolute(relative)) === expected.link, `Code link changed after planning: ${relative}`);
  }
}

function acquire(tree, relative, executable, handles) {
  ensure(executable && path.isAbsolute(executable), 'DSH_RETENTION_FLOCK must name the absolute util-linux flock executable');
  const stat = tree.stat(relative);
  ensure(stat.isFile() && stat.nlink === 1n, `Lock must be a regular, single-link stable file: ${relative}`);
  const fd = fs.openSync(tree.absolute(relative), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  handles.push({ fd, relative, stat: identity(stat) });
  ensure(JSON.stringify(identity(fs.fstatSync(fd, { bigint: true }))) === JSON.stringify(identity(stat)), `Lock inode changed: ${relative}`);
  const result = spawnSync(executable, ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'pipe', 'pipe', fd], timeout: 5000 });
  ensure(!result.error && result.status === 0, result.status === 75 ? `Live lock: ${relative}; stop all packaged DSH writers before maintenance` : `Unable to acquire exclusive flock: ${relative}`);
  ensure(/\bFLOCK\s+ADVISORY\s+WRITE\b/.test(fs.readFileSync(`/proc/self/fdinfo/${fd}`, 'utf8')), `Exclusive flock was not established: ${relative}`);
  tree.assertUnchanged(relative, identity(stat));
}

function collect(value, refs, label, depth = 0, active = new Set()) {
  ensure(depth <= 100 && !active.has(value), `Reference nesting or alias cycle exceeds scan bounds: ${label}`);
  if (typeof value === 'string') {
    collectDigests(value, refs);
    if (/attachments[\\/\\\\]/i.test(value) && !/[a-f0-9]{64}/i.test(value)) fail(`Unrecognized attachment storage reference in ${label}`);
  } else if (Array.isArray(value) || object(value)) {
    active.add(value);
    for (const [key, item] of Object.entries(value)) {
      if (['attachmentId', 'variantId'].includes(key)) ensure(typeof item === 'string' && /^sha256:[a-f0-9]{64}$/.test(item), `Unsupported attachment reference in ${label}`);
      collect(key, refs, label, depth + 1, active);
      collect(item, refs, label, depth + 1, active);
    }
    active.delete(value);
  }
}

function parseJson(data, label) {
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(data)); }
  catch { fail(`Malformed JSON or UTF-8: ${label}`); }
}

function scanLog(tree, relative, version, catalog) {
  const { data, stat } = tree.read(relative);
  let decoded = data;
  if (relative.endsWith('.zstd')) {
    ensure(typeof zlib.zstdDecompressSync === 'function', `Zstandard is unsupported by this Node runtime: ${relative}`);
    try {
      const frames = [];
      let offset = 0;
      let size = 0;
      while (offset < data.length) {
        ensure(data.length - offset >= 4 && data.readUInt32LE(offset) === 0xFD2FB528, 'Invalid Zstandard frame magic');
        const frame = zlib.zstdDecompressSync(data.subarray(offset), { maxOutputLength: MAX_FILE - size, info: true });
        const consumed = frame.engine.bytesWritten;
        ensure(Number.isSafeInteger(consumed) && consumed > 0 && consumed <= data.length - offset, 'Invalid Zstandard frame boundary');
        offset += consumed;
        size += frame.buffer.length;
        ensure(size < MAX_FILE && frames.length < MAX_ENTRIES, 'Zstandard expansion limit exceeded');
        frames.push(frame.buffer);
      }
      decoded = Buffer.concat(frames, size);
    } catch { fail(`Corrupt or unsupported Zstandard log: ${relative}`); }
    tree.total += decoded.length;
    ensure(tree.total <= MAX_TOTAL, 'Total decompressed scan byte limit exceeded');
  }
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(decoded); }
  catch { fail(`Malformed UTF-8 log: ${relative}`); }
  ensure(text.endsWith('\n'), `Incomplete session log: ${relative}`);
  const lines = text.slice(0, -1).split('\n');
  const header = parseJson(Buffer.from(lines[0]), relative);
  ensure(object(header) && header.type === 'session' && header.version === version && typeof header.id === 'string' && header.id.length > 0, `Invalid session header or version: ${relative}`);
  const refs = new Set();
  collect(header, refs, relative);
  let lastActivity = Math.max(header.createdAt, Number(stat.mtimeMs));
  try {
    const restore = (version === 4 ? catalog.sessionFormatCatalog : catalog.historicalSessionFormatCatalog).createRestore(header, { recovery: 'strict', validation: 'current' });
    for (let index = 1; index < lines.length; index++) {
      const row = parseJson(Buffer.from(lines[index]), relative);
      ensure(object(row) && row.ignorable !== true, `Unknown or ignorable event requires manual review: ${relative}`);
      collect(row, refs, relative);
      restore.decodeRow(row);
      if (Number.isSafeInteger(row.time)) lastActivity = Math.max(lastActivity, row.time);
    }
    for (const event of restore.finish().events) {
      lastActivity = Math.max(lastActivity, event.time);
      if (event.type !== 'assistant/attempt' && event.type !== 'assistant/message') continue;
      for (const part of event.data.stream) {
        if (Number.isSafeInteger(part.time)) lastActivity = Math.max(lastActivity, part.time);
        if (Number.isSafeInteger(part.time0)) {
          let time = part.time0;
          lastActivity = Math.max(lastActivity, time);
          for (const delta of part.dt) {
            time += delta;
            lastActivity = Math.max(lastActivity, time);
          }
        }
      }
    }
  } catch (error) { fail(`Invalid or unsupported session log ${relative}: ${error.message}`); }
  return { header, refs, lastActivity, path: relative };
}

const ROOT_FILES = new Set(['.operations.lock', '.anonymous-user-id', '.credentials.yaml', '.env', 'cordis.patch.yml', 'settings.yaml', 'settings.yaml.imported', 'package.json', 'pnpm-lock.yaml']);
const ROOT_DIRS = new Set(['sessions', 'attachments', 'storages', 'profiles', 'cache', 'skills', 'logs', 'node_modules', 'operations', 'plugins']);
const AUXILIARY_DIRS = new Set(['profiles', 'cache', 'skills', 'logs', 'node_modules', 'operations', 'plugins']);

function scan(tree, opts, catalog, executable, handles, lockSessions, catalogPath, nodeModules) {
  const rootNames = tree.directory('');
  ensure(rootNames.includes('sessions'), 'Refusing unexpected root without sessions directory');
  const auxiliary = [];
  for (const name of rootNames) {
    const stat = tree.stat(name, name === 'node_modules');
    ensure(stat.isDirectory() || stat.isSymbolicLink() ? ROOT_DIRS.has(name) : ROOT_FILES.has(name), `Unrecognized DSH_HOME entry: ${name}`);
    if (AUXILIARY_DIRS.has(name)) {
      const children = stat.isSymbolicLink() ? ['immutable-code'] : tree.directory(name);
      if (children.length) auxiliary.push(name);
    }
  }
  const auxiliaryRefs = new Set();
  const auxiliaryScan = scanAuxiliary(tree, rootNames, auxiliaryRefs, { collect, parseJson, hash, identity, catalogPath, nodeModules, gc: opts.gc });
  const sessions = [];
  const seenIds = new Set();
  for (const project of tree.directory('sessions')) {
    ensure(project === '_no-cwd' || /^--[A-Za-z0-9._~\-]+--$/.test(project), `Unrecognized project directory: ${project}`);
    for (const encoded of tree.directory(`sessions/${project}`)) {
      ensure(/^(?:[A-Za-z0-9._-]|~[A-F0-9]{4})+$/.test(encoded) && !['.', '..'].includes(encoded), `Invalid encoded session directory: ${encoded}`);
      const dir = `sessions/${project}/${encoded}`;
      const children = tree.directory(dir);
      if (children.includes('session.lock')) {
        if (lockSessions) acquire(tree, `${dir}/session.lock`, executable, handles);
        tree.read(`${dir}/session.lock`);
      }
      const logs = [];
      const versions = new Set();
      for (const name of children) {
        if (name === 'session.lock') continue;
        const match = /^session(?:\.v([1-4]))?\.jsonl(\.zstd)?$/.exec(name);
        ensure(match, `Unknown session artifact, backup, or version: ${dir}/${name}`);
        const version = Number(match[1] ?? 0);
        ensure(!versions.has(version), `Ambiguous session generation: ${dir}`);
        versions.add(version);
        logs.push(scanLog(tree, `${dir}/${name}`, version, catalog));
      }
      if (!logs.length) continue;
      const header = logs[0].header;
      ensure(encode(header.id) === encoded, `Session id does not match directory: ${dir}`);
      ensure(projectKey(header.cwd) === project, `Session cwd does not match project directory: ${dir}`);
      ensure(!seenIds.has(header.id), `Duplicate session id: ${header.id}`);
      seenIds.add(header.id);
      for (const log of logs) ensure(log.header.id === header.id && log.header.createdAt === header.createdAt && log.header.cwd === header.cwd, `Conflicting generation identity: ${dir}`);
      sessions.push({ id: header.id, createdAt: header.createdAt, paths: logs.map(log => log.path), refs: new Set(logs.flatMap(log => [...log.refs])), lastActivity: Math.max(...logs.map(log => log.lastActivity)) });
    }
  }
  const selected = sessions.filter(session => opts.ids.includes(session.id) || (opts.olderThan !== undefined && session.lastActivity < opts.olderThan));
  for (const id of opts.ids) ensure(selected.some(session => session.id === id), `Requested session id not found: ${id}`);
  ensure(selected.length <= opts.max, 'Session selection exceeds --max; narrow the selection');
  const selectedIds = new Set(selected.map(session => session.id));
  const removals = selected.flatMap(session => session.paths.map(relative => ({ path: relative, kind: 'session-log', sessionId: session.id })));
  const refs = new Set([...auxiliaryRefs, ...sessions.filter(session => !selectedIds.has(session.id)).flatMap(session => [...session.refs])]);
  const leftovers = { auxiliary, workspaceSessionIds: [], orphanProjectionIds: [], legacyProjection: false };
  const workspace = rootNames.includes('storages') ? scanStorages(tree, selected, sessions, refs, removals, leftovers) : null;
  const attachmentGroups = rootNames.includes('attachments') ? scanAttachments(tree) : new Map();
  const attachmentCutoff = opts.asOf - opts.graceDays * DAY;
  let protectedAttachments = 0;
  for (const [digest, group] of attachmentGroups) {
    if (!opts.gc || refs.has(digest) || group.some(item => Math.max(Number(item.stat.mtimeMs), Number(item.stat.ctimeMs)) >= attachmentCutoff)) { protectedAttachments++; continue; }
    for (const item of group) removals.push({ path: item.path, kind: 'attachment', digest });
  }
  removals.sort((a, b) => a.kind === b.kind ? a.path.localeCompare(b.path, 'en') : a.kind === 'attachment' ? 1 : b.kind === 'attachment' ? -1 : a.path.localeCompare(b.path, 'en'));
  ensure(removals.length <= opts.max, 'File removal count exceeds --max; narrow the selection or increase the bound');
  const parameters = { ids: opts.ids, olderThan: opts.olderThan === undefined ? null : new Date(opts.olderThan).toISOString(), asOf: new Date(opts.asOf).toISOString(), max: opts.max, gcAttachments: opts.gc, attachmentGraceDays: opts.graceDays };
  const plan = {
    version: 2,
    home: tree.home,
    parameters,
    selectedSessionIds: [...selectedIds].sort(),
    remove: removals.map(item => ({ ...item, bytes: Number(tree.snapshot.get(item.path).size) })),
    protectedAttachmentDigests: protectedAttachments,
    leftovers,
    auxiliaryScan,
    workspaceUpdate: workspace ? { path: workspacePath, beforeHash: workspace.beforeHash, afterHash: workspace.afterHash, removeSessionIds: workspace.removeSessionIds } : null,
    semantics: 'Atomically prune selected session IDs from known workspace-v2 metadata with a durable rollback journal before unlinking listed logs, matching derived records, and eligible attachments. Preserve every lock inode, directory, and non-selection workspace field. Not secure erasure: retained logs, caches, exports, external stores, backups, and remote-provider copies are never erased. Only cooperating packaged writers are excluded.',
    snapshotHash: hash(JSON.stringify([...tree.snapshot].sort(([a], [b]) => a.localeCompare(b, 'en')))),
  };
  return { plan, planHash: hash(JSON.stringify(plan)), workspace };
}

function scanStorages(tree, selected, sessions, refs, removals, leftovers) {
  const names = tree.directory('storages');
  ensure(!names.includes(path.basename(journalPath)), 'Interrupted workspace retention; run recover-workspace --home DSH_HOME --confirm RECOVER-WORKSPACE before preview');
  let workspace = null;
  const selectedById = new Map(selected.map(session => [session.id, session]));
  const knownIds = new Set(sessions.map(session => session.id));
  const projection = (doc, label) => {
    ensure(object(doc) && [3, 4, 5, 6, 7].includes(doc.version) && object(doc.record) && object(doc.record.identity) && Number.isSafeInteger(doc.record.identity.createdAt) && object(doc.record.rows), `Unknown or malformed projection record: ${label}`);
    ensure(Object.keys(doc).every(key => ['version', 'record'].includes(key)), `Unknown projection envelope: ${label}`);
    for (const row of Object.values(doc.record.rows)) ensure(object(row) && Number.isSafeInteger(row.ver) && row.ver >= 0 && Number.isSafeInteger(row.seq) && row.seq >= -1 && Object.hasOwn(row, 'val'), `Malformed projection row: ${label}`);
  };
  for (const name of names) {
    const relative = `storages/${name}`;
    if (name === 'workspace.json') {
      const before = tree.read(relative).data;
      ensure(before.length <= 16 * 1024 * 1024, 'Workspace exceeds transaction byte bound');
      const doc = parseJson(before, relative);
      const { after, removed } = pruneWorkspace(doc, new Set(selectedById.keys()));
      if (removed.length) {
        const data = Buffer.from(`${JSON.stringify(after, null, 2)}\n`);
        workspace = { beforeHash: hash(before), afterHash: hash(data), data, removeSessionIds: removed };
      }
      collect(doc, refs, relative);
    } else if (name === 'session_projcache') {
      ensure(tree.directory(relative).every(entry => entry === 'sessions'), 'Unrecognized projection storage entry');
      const directory = `${relative}/sessions`;
      if (!tree.snapshot.get(relative).children.includes('sessions')) continue;
      for (const file of tree.directory(directory)) {
        ensure(/^[A-Za-z0-9_-]+\.json$/.test(file), `Unrecognized projection artifact or backup: ${file}`);
        const recordPath = `${directory}/${file}`;
        const doc = parseJson(tree.read(recordPath).data, recordPath);
        projection(doc, recordPath);
        const id = file.slice(0, -5);
        if (selectedById.has(id)) {
          ensure(doc.record.identity.createdAt === selectedById.get(id).createdAt, `Projection lifecycle mismatch: ${id}`);
          removals.push({ path: recordPath, kind: 'projection', sessionId: id });
        } else {
          collect(doc, refs, recordPath);
          if (!knownIds.has(id)) leftovers.orphanProjectionIds.push(id);
        }
      }
    } else if (name === 'session_projcache.json') {
      const doc = parseJson(tree.read(relative).data, relative);
      ensure(object(doc) && object(doc.unit) && doc.unit.name === 'session_projcache' && [3, 4, 5, 6, 7].includes(doc.unit.version) && object(doc.tables) && object(doc.tables.sessions), 'Unknown legacy projection storage');
      ensure(Object.keys(doc.tables).every(key => key === 'sessions'), 'Unknown legacy projection table');
      for (const [id, record] of Object.entries(doc.tables.sessions)) {
        projection({ version: doc.unit.version, record }, relative);
        ensure(!selectedById.has(id), 'Selected session still exists in legacy projection storage; refusing incomplete deletion');
      }
      leftovers.legacyProjection = true;
      collect(doc, refs, relative);
    } else if (name === 'schedule.json') {
      const doc = parseJson(tree.read(relative).data, relative);
      ensure(object(doc) && object(doc.unit) && doc.unit.name === 'schedule' && doc.unit.version === 1 && object(doc.tables) && object(doc.tables.tasks) && Object.keys(doc.tables).every(key => ['tasks', 'outbox'].includes(key)), 'Unknown schedule storage');
      if (Object.hasOwn(doc.tables, 'outbox')) {
        ensure(object(doc.tables.outbox), 'Unknown schedule outbox storage');
        for (const [id, entry] of Object.entries(doc.tables.outbox)) {
          ensure(object(entry) && Object.keys(entry).every(key => ['id', 'sessionId', 'text', 'members', 'attempts', 'retryAt', 'deliveredAt', 'recoveryCount', 'totalAttempts'].includes(key)) && entry.id === id && typeof entry.id === 'string' && entry.id.length > 0 && typeof entry.sessionId === 'string' && entry.sessionId.length > 0 && typeof entry.text === 'string' && Array.isArray(entry.members) && entry.members.length > 0 && Number.isSafeInteger(entry.attempts) && entry.attempts >= 0 && entry.attempts <= 5 && Number.isSafeInteger(entry.retryAt) && entry.retryAt >= 0 && (entry.deliveredAt === undefined || typeof entry.deliveredAt === 'string'), 'Unknown or malformed schedule outbox record');
          const recoveryFields = Object.hasOwn(entry, 'recoveryCount') || Object.hasOwn(entry, 'totalAttempts');
          ensure(!recoveryFields || (Number.isSafeInteger(entry.recoveryCount) && entry.recoveryCount >= 0 && entry.recoveryCount <= 100 && Number.isSafeInteger(entry.totalAttempts) && entry.totalAttempts === 5 * entry.recoveryCount + entry.attempts), 'Unknown schedule recovery provenance');
          for (const member of entry.members) ensure(object(member) && Object.keys(member).every(key => ['taskId', 'prompt', 'scheduledAt', 'nextScheduledAt', 'targetAt'].includes(key)) && typeof member.taskId === 'string' && member.taskId.length > 0 && typeof member.prompt === 'string' && typeof member.scheduledAt === 'string' && (member.nextScheduledAt === undefined || typeof member.nextScheduledAt === 'string') && (member.targetAt === undefined || typeof member.targetAt === 'string'), 'Unknown or malformed schedule outbox member');
        }
      }
      collect(doc, refs, relative);
    } else fail(`Unrecognized storage or backup: ${relative}`);
  }
  return workspace;
}

function scanAttachments(tree) {
  ensure(tree.directory('attachments').every(name => name === 'v1'), 'Unknown attachment storage version');
  const groups = new Map();
  if (!tree.snapshot.get('attachments').children.includes('v1')) return groups;
  const root = 'attachments/v1';
  const names = tree.directory(root);
  for (const name of names) {
    ensure(['objects', 'file-objects', 'files', 'tmp'].includes(name), `Unrecognized attachment store: ${name}`);
    const directory = `${root}/${name}`;
    if (name === 'tmp') {
      ensure(tree.directory(directory).length === 0, 'Pending attachment uploads exist; refusing maintenance');
      continue;
    }
    for (const prefix of tree.directory(directory)) {
      ensure(/^[a-f0-9]{2}$/.test(prefix), 'Invalid attachment shard');
      for (const digest of tree.directory(`${directory}/${prefix}`)) {
        ensure(/^[a-f0-9]{64}$/.test(digest) && digest.startsWith(prefix), 'Invalid attachment digest path');
        const location = `${directory}/${prefix}/${digest}`;
        const files = name === 'files' ? tree.directory(location).map(leaf => `${location}/${leaf}`) : [location];
        for (const relative of files) {
          const item = tree.read(relative, true);
          ensure(item.entry.sha256 === digest, `Corrupt attachment digest: ${relative}`);
          const group = groups.get(digest) ?? [];
          group.push({ path: relative, stat: item.stat });
          groups.set(digest, group);
        }
      }
    }
  }
  const inodes = new Map();
  for (const group of groups.values()) for (const item of group) {
    const key = `${item.stat.dev}:${item.stat.ino}`;
    const aliases = inodes.get(key) ?? [];
    aliases.push(item);
    inodes.set(key, aliases);
  }
  for (const aliases of inodes.values()) ensure(BigInt(aliases.length) === aliases[0].stat.nlink, `Attachment has unaccounted hardlinks: ${aliases[0].path}`);
  return groups;
}

function syncParents(tree, parents) {
  const failures = [];
  for (const parent of parents) {
    try {
      ensure(tree.stat(parent).isDirectory(), `Expected deletion parent directory: ${parent}`);
      const fd = fs.openSync(tree.absolute(parent), fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
      try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
      parents.delete(parent);
    } catch (error) { failures.push(`${parent}: ${error.message}`); }
  }
  ensure(failures.length === 0, `Directory synchronization failed: ${failures.join('; ')}`);
}

const HELP = 'Offline retention: stop all packaged DSH writers. Preview uses --home /absolute/DSH_HOME with --id ID or --older-than ISO_TIMESTAMP; --gc-attachments opts into bounded conservative reference scanning and a minimum seven-day grace. Apply repeats selectors plus --as-of TIMESTAMP --plan-hash HASH --confirm DELETE:HASH. Workspace-v2 selected session IDs are atomically pruned with a durable rollback journal before log deletion. Interrupted workspace transactions require recover-workspace --home /absolute/DSH_HOME --confirm RECOVER-WORKSPACE. Not secure erasure: exports, backups, retained caches, external stores and remote-provider copies are never erased.';

export async function run(argv, env = process.env) {
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) return { help: HELP };
  ensure(process.platform === 'linux', 'Retention maintenance requires Linux flock and /proc');
  const opts = options(argv);
  const tree = new Tree(opts.home);
  const handles = [];
  const removed = [];
  const parents = new Set();
  let journalAttempted = false;
  try {
    acquire(tree, '.operations.lock', env.DSH_RETENTION_FLOCK, handles);
    if (tree.directory('').includes('operations') && tree.directory('operations').includes('migrations')) ensure(!tree.directory('operations/migrations').includes('active.json'), 'Unfinished storage migration; retention is blocked until migration recovery completes');
    if (opts.action === 'recover-workspace') return recoverWorkspace(tree, { hash, parseJson, syncParents }, relative => acquire(tree, relative, env.DSH_RETENTION_FLOCK, handles));
    ensure(env.DSH_RETENTION_CATALOG && path.isAbsolute(env.DSH_RETENTION_CATALOG), 'DSH_RETENTION_CATALOG must name the pinned session-format-catalog module');
    const catalog = await import(pathToFileURL(env.DSH_RETENTION_CATALOG).href);
    ensure(catalog.sessionFormatCatalog?.currentVersion === 4 && catalog.historicalSessionFormatCatalog?.currentVersion === 3, 'Unsupported pinned session format catalogs; expected v4 and historical v3');
    const first = scan(tree, opts, catalog, env.DSH_RETENTION_FLOCK, handles, true, env.DSH_RETENTION_CATALOG, env.DSH_RETENTION_NODE_MODULES);
    if (opts.action === 'preview') return { plan: first.plan, planHash: first.planHash, confirmationToken: `DELETE:${first.planHash}` };
    ensure(first.planHash === opts.planHash, 'Plan hash mismatch; storage or selection changed; preview again');
    const finalTree = new Tree(opts.home);
    const second = scan(finalTree, opts, catalog, env.DSH_RETENTION_FLOCK, handles, false, env.DSH_RETENTION_CATALOG, env.DSH_RETENTION_NODE_MODULES);
    ensure(second.planHash === first.planHash, 'Storage changed during apply; preview again');
    for (const handle of handles) finalTree.assertUnchanged(handle.relative, handle.stat);
    for (const [relative, expected] of finalTree.snapshot) finalTree.assertUnchanged(relative, expected);
    finalTree.total = 0;
    journalAttempted = Boolean(second.workspace);
    const transaction = beginWorkspace(finalTree, second.workspace, second.plan, { hash, syncParents });
    const deletedLinks = new Map();
    let referencesDurable = false;
    for (const item of second.plan.remove) {
      if (item.kind === 'attachment' && !referencesDurable) {
        syncParents(finalTree, parents);
        referencesDurable = true;
      }
      ensure(item.kind === 'attachment' ? item.path.startsWith('attachments/v1/') : item.kind === 'session-log' ? /^sessions\/[^/]+\/[^/]+\/session(?:\.v[1-4])?\.jsonl(?:\.zstd)?$/.test(item.path) : /^storages\/session_projcache\/sessions\/[A-Za-z0-9_-]+\.json$/.test(item.path), 'Unexpected deletion target');
      finalTree.assertUnchanged('.operations.lock', handles[0].stat);
      const expected = finalTree.snapshot.get(item.path);
      const key = `${expected.dev}:${expected.ino}`;
      const count = deletedLinks.get(key) ?? 0;
      const current = finalTree.stat(item.path);
      const adjusted = { ...expected, nlink: String(BigInt(expected.nlink) - BigInt(count)) };
      if (count) adjusted.ctimeNs = String(current.ctimeNs);
      finalTree.assertUnchanged(item.path, adjusted);
      const checked = finalTree.read(item.path, item.kind === 'attachment');
      ensure(checked.entry.sha256 === expected.sha256, `Content changed before unlink: ${item.path}`);
      fs.unlinkSync(finalTree.absolute(item.path));
      removed.push(item.path);
      parents.add(path.dirname(item.path));
      deletedLinks.set(key, count + 1);
    }
    syncParents(finalTree, parents);
    finishWorkspace(finalTree, transaction, { hash, syncParents });
    return { applied: true, planHash: second.planHash, removed, workspaceUpdate: second.plan.workspaceUpdate, leftovers: second.plan.leftovers, semantics: second.plan.semantics };
  } catch (error) {
    if (journalAttempted) {
      try {
        if (fs.readdirSync(tree.absolute('storages')).includes(path.basename(journalPath))) {
          if (!removed.some(relative => relative.startsWith('sessions/'))) {
            recoverWorkspace(new Tree(opts.home), { hash, parseJson, syncParents }, () => {});
            error.message += '; workspace selection metadata rolled back';
          } else error.message += '; workspace journal retained; run recover-workspace --confirm RECOVER-WORKSPACE';
        }
      } catch (recoveryError) {
        if (recoveryError.code !== 'ENOENT') error.message += `; workspace recovery required: ${recoveryError.message}`;
      }
    }
    if (removed.length) {
      error.message += `; partial apply, already unlinked: ${JSON.stringify(removed)}; no rollback, preview again`;
      try { syncParents(tree, parents); }
      catch (syncError) { error.message += `; deletions may not be durable: ${syncError.message}`; }
    }
    throw error;
  } finally {
    for (const handle of handles.reverse()) fs.closeSync(handle.fd);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await run(process.argv.slice(2)), null, 2)); }
  catch (error) { console.error(`Retention refused: ${error.message}`); process.exitCode = 1; }
}
