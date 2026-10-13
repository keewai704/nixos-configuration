import fs from 'node:fs';
import path from 'node:path';

export const workspacePath = 'storages/workspace.json';
export const journalPath = 'storages/.retention-workspace.json';
const temporaryPath = 'storages/.retention-workspace.tmp';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const ensure = (condition, message) => { if (!condition) throw new Error(message); };
const keys = (value, allowed) => object(value) && Object.keys(value).every(key => allowed.includes(key));
const strings = value => Array.isArray(value) && value.every(item => typeof item === 'string') && new Set(value).size === value.length;

export function pruneWorkspace(doc, selectedIds) {
  ensure(keys(doc, ['unit', 'global', 'tables']) && keys(doc.unit, ['name', 'version']) && doc.unit.name === 'workspace' && doc.unit.version === 2 && keys(doc.tables, ['workspaces']) && object(doc.tables.workspaces), 'Unknown or malformed workspace storage');
  ensure(keys(doc.global, ['initialized', 'defaultWorkspaceId', 'workspaceIds', 'archivedSessionIds', 'pinnedSessionIds', 'pendingMutation']), 'Unknown workspace global fields');
  ensure(!Object.hasOwn(doc.global, 'pendingMutation'), 'Workspace has an unfinished mutation');
  ensure(typeof doc.global.initialized === 'boolean' && strings(doc.global.workspaceIds), 'Malformed workspace global record');
  ensure(doc.global.defaultWorkspaceId === undefined || typeof doc.global.defaultWorkspaceId === 'string', 'Malformed default workspace identity');
  const ids = Object.keys(doc.tables.workspaces);
  ensure(ids.length === doc.global.workspaceIds.length && ids.every(id => doc.global.workspaceIds.includes(id)), 'Workspace order and records disagree');
  const accounted = new Set();
  for (const record of Object.values(doc.tables.workspaces)) {
    ensure(keys(record, ['path', 'title', 'createdAt', 'updatedAt', 'sessionIds']) && ['path', 'title', 'createdAt', 'updatedAt'].every(key => typeof record[key] === 'string') && strings(record.sessionIds), 'Unknown or malformed workspace record');
    for (const id of record.sessionIds) {
      ensure(!accounted.has(id), 'Workspace session ownership is ambiguous');
      accounted.add(id);
    }
  }
  for (const key of ['archivedSessionIds', 'pinnedSessionIds']) {
    if (doc.global[key] === undefined) continue;
    ensure(strings(doc.global[key]), 'Malformed workspace session references');
  }
  ensure(!(doc.global.archivedSessionIds ?? []).some(id => doc.global.pinnedSessionIds?.includes(id)), 'Workspace pin and archive sets conflict');
  const removed = new Set();
  const filter = ids => ids.filter(id => {
    if (!selectedIds.has(id)) return true;
    removed.add(id);
    return false;
  });
  const after = structuredClone(doc);
  for (const record of Object.values(after.tables.workspaces)) record.sessionIds = filter(record.sessionIds);
  for (const key of ['archivedSessionIds', 'pinnedSessionIds']) if (after.global[key]) after.global[key] = filter(after.global[key]);
  return { after, removed: [...removed].sort() };
}

function durableCreate(tree, relative, data, mode = 0o600) {
  ensure(relative === journalPath || relative === temporaryPath, 'Unexpected retention transaction path');
  tree.stat('storages');
  const fd = fs.openSync(tree.absolute(relative), fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, mode);
  try { fs.writeFileSync(fd, data); fs.fchmodSync(fd, mode); fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
}

function checkedUnlink(tree, relative, expectedHash, hash) {
  ensure([journalPath, temporaryPath].includes(relative), 'Unexpected retention cleanup target');
  const { data, stat } = tree.read(relative);
  ensure(hash(data) === expectedHash && stat.nlink === 1n, `Retention transaction changed: ${relative}`);
  ensure(tree.absolute(relative) === path.join(tree.home, relative), 'Unexpected retention cleanup path');
  fs.unlinkSync(tree.absolute(relative));
}

function replace(tree, currentHash, data, mode, helpers) {
  const { hash, syncParents } = helpers;
  durableCreate(tree, temporaryPath, data, mode);
  const current = tree.read(workspacePath);
  ensure(hash(current.data) === currentHash && current.stat.nlink === 1n, 'Workspace changed during retention transaction');
  const staged = tree.read(temporaryPath);
  ensure(hash(staged.data) === hash(data), 'Staged workspace changed');
  ensure(tree.absolute(temporaryPath) === path.join(tree.home, temporaryPath) && tree.absolute(workspacePath) === path.join(tree.home, workspacePath), 'Unexpected workspace replacement path');
  fs.renameSync(tree.absolute(temporaryPath), tree.absolute(workspacePath));
  syncParents(tree, new Set(['storages']));
}

export function beginWorkspace(tree, update, plan, helpers) {
  if (!update) return null;
  const { hash, syncParents } = helpers;
  const before = tree.read(workspacePath);
  ensure(hash(before.data) === update.beforeHash, 'Workspace changed before transaction');
  const journal = {
    version: 1,
    planHash: hash(JSON.stringify(plan)),
    selectedSessionIds: plan.selectedSessionIds,
    sessionLogs: plan.remove.filter(item => item.kind === 'session-log').map(item => item.path),
    before: before.data.toString('base64'),
    beforeHash: update.beforeHash,
    afterHash: update.afterHash,
    mode: Number(before.stat.mode & 0o777n),
  };
  const data = Buffer.from(`${JSON.stringify(journal)}\n`);
  durableCreate(tree, journalPath, data);
  syncParents(tree, new Set(['storages']));
  const transaction = { ...journal, journalHash: hash(data), after: update.data };
  replace(tree, update.beforeHash, update.data, journal.mode, helpers);
  return transaction;
}

export function finishWorkspace(tree, transaction, helpers) {
  if (!transaction) return;
  checkedUnlink(tree, journalPath, transaction.journalHash, helpers.hash);
  helpers.syncParents(tree, new Set(['storages']));
}

export function recoverWorkspace(tree, helpers, acquireSession) {
  const { hash, parseJson, syncParents } = helpers;
  const names = tree.directory('storages');
  ensure(names.includes(path.basename(journalPath)), 'No retention workspace journal to recover');
  const stored = tree.read(journalPath);
  const journal = parseJson(stored.data, journalPath);
  ensure(keys(journal, ['version', 'planHash', 'selectedSessionIds', 'sessionLogs', 'before', 'beforeHash', 'afterHash', 'mode']) && journal.version === 1 && /^[a-f0-9]{64}$/.test(journal.planHash) && strings(journal.selectedSessionIds) && strings(journal.sessionLogs) && journal.sessionLogs.length > 0 && journal.sessionLogs.length <= 1000 && typeof journal.before === 'string' && /^[A-Za-z0-9+/]*={0,2}$/.test(journal.before) && Number.isInteger(journal.mode) && journal.mode >= 0 && journal.mode <= 0o777 && (journal.mode & 0o022) === 0, 'Unknown retention workspace journal');
  ensure(journal.before.length <= 24 * 1024 * 1024, 'Workspace recovery exceeds byte bound');
  const before = Buffer.from(journal.before, 'base64');
  ensure(before.toString('base64') === journal.before && hash(before) === journal.beforeHash, 'Corrupt workspace rollback bytes');
  const { after } = pruneWorkspace(parseJson(before, workspacePath), new Set(journal.selectedSessionIds));
  const afterData = Buffer.from(`${JSON.stringify(after, null, 2)}\n`);
  ensure(hash(afterData) === journal.afterHash, 'Corrupt workspace replacement hash');
  let missing = false;
  const locked = new Set();
  for (const relative of journal.sessionLogs) {
    ensure(/^sessions\/[^/]+\/[^/]+\/session(?:\.v[1-4])?\.jsonl(?:\.zstd)?$/.test(relative) && !relative.split('/').some(part => ['.', '..'].includes(part)), 'Unsafe retention journal log path');
    const directory = path.dirname(relative);
    const children = tree.directory(directory);
    const lock = `${directory}/session.lock`;
    if (children.includes('session.lock') && !locked.has(lock)) { acquireSession(lock); locked.add(lock); }
    if (!children.includes(path.basename(relative))) missing = true;
    else tree.read(relative);
  }
  const current = tree.read(workspacePath);
  const currentHash = hash(current.data);
  ensure(currentHash === journal.beforeHash || currentHash === journal.afterHash, 'Workspace changed since interrupted retention; manual recovery required');
  if (names.includes(path.basename(temporaryPath))) {
    const staged = tree.read(temporaryPath);
    const digest = hash(staged.data);
    const prefix = [before, afterData].some(data => staged.data.length < data.length && staged.data.equals(data.subarray(0, staged.data.length)));
    ensure([journal.beforeHash, journal.afterHash].includes(digest) || prefix, 'Unknown interrupted workspace temporary file');
    checkedUnlink(tree, temporaryPath, digest, hash);
    syncParents(tree, new Set(['storages']));
  }
  const target = missing ? afterData : before;
  if (currentHash !== hash(target)) replace(tree, currentHash, target, journal.mode, helpers);
  syncParents(tree, new Set(journal.sessionLogs.map(relative => path.dirname(relative))));
  checkedUnlink(tree, journalPath, hash(stored.data), hash);
  syncParents(tree, new Set(['storages']));
  return { recovered: true, workspace: missing ? 'kept-pruned-after-log-deletion' : 'rolled-back-before-log-deletion', semantics: 'Recovery changes only workspace session-ID metadata and its retention journal; it does not restore deleted logs or erase external copies.' };
}
