import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { SafeTree, hash, directoryIdentity } from './migrate-fs.mjs';
import { migration, parseJson, encodeJson, ensure, MAX_TOTAL, object } from './migrate-registry.mjs';

export const ACTIVE_PATH = 'operations/migrations/active.json';
const ROOT = 'operations/migrations';
const ID = /^[a-f0-9]{64}$/;
const equal = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const serial = index => String(index).padStart(6, '0');
const terminal = status => ['COMMITTED', 'ROLLED_BACK'].includes(status);

function assertNoActive(tree) {
  ensure(tree.stat(ACTIVE_PATH, true) === null, `Active migration gate ${ACTIVE_PATH}; recover before any other maintenance or launch`);
}

function layout(tree, edge) {
  const result = [];
  for (const relative of edge.directories) {
    const stat = tree.stat(relative, true);
    if (stat) {
      ensure(stat.isDirectory(), `Expected migration directory: ${relative}`);
      const entries = tree.entries(relative);
      const allowed = relative === edge.directories[0] ? ['sessions'] : [];
      ensure(entries.every(name => allowed.includes(name)), `Existing per-record content prevents migration: ${relative}`);
    }
    result.push({ path: relative, before: stat ? directoryIdentity(stat) : null });
  }
  return result;
}

function buildPlan(tree, migrationId) {
  assertNoActive(tree);
  const edge = migration(migrationId);
  const source = tree.read(edge.source);
  const files = edge.transform(parseJson(source.data));
  ensure(source.data.length + files.reduce((total, file) => total + file.data.length * 2, 0) <= MAX_TOTAL, 'Migration aggregate byte bound exceeded');
  const directories = layout(tree, edge);
  const plan = {
    schemaVersion: 1,
    migration: edge.id,
    revision: edge.revision,
    inputSchema: edge.inputSchema,
    outputSchema: edge.outputSchema,
    home: tree.home,
    root: tree.handles.get('').info,
    storage: directoryIdentity(tree.stat('storages')),
    lock: tree.lock.info,
    source: { path: edge.source, sha256: source.sha256, bytes: source.data.length, identity: source.identity },
    directories,
    files: files.map(file => ({ path: file.path, before: null, afterSha256: hash(file.data), afterBytes: file.data.length })),
    priorTransactions: tree.stat(ROOT, true) ? tree.entries(ROOT).filter(name => ID.test(name)).map(name => {
      ensure(tree.stat(`${ROOT}/${name}`).isDirectory(), 'Unsafe migration history entry');
      return name;
    }) : [],
    semantics: edge.semantics,
  };
  return { plan, planHash: hash(encodeJson(plan)), source, files };
}

function ensureDirectory(tree, relative) {
  const info = tree.stat(relative, true);
  if (!info) tree.mkdir(relative);
  else { ensure(info.isDirectory(), `Expected metadata directory: ${relative}`); tree.directory(relative); }
}

function publishJson(tree, relative, value) {
  const existing = tree.stat(relative, true) ? tree.read(relative) : null;
  const temporary = `${path.posix.dirname(relative)}/.${path.posix.basename(relative)}-${randomBytes(8).toString('hex')}.tmp`;
  const written = tree.writeNew(temporary, encodeJson(value));
  tree.rename(temporary, relative, written, existing);
}

function manifestPath(transaction) { return `${ROOT}/${transaction}/manifest.json`; }
function backupPath(transaction) { return `${ROOT}/${transaction}/source.bin`; }
function afterPath(transaction, index) { return `${ROOT}/${transaction}/${serial(index)}.after.json`; }
function stagePath(transaction, index) { return `${ROOT}/${transaction}/${serial(index)}.stage`; }

function setManifest(tree, manifest, status) {
  manifest.status = status;
  publishJson(tree, manifestPath(manifest.transaction), manifest);
}

function setActive(tree, manifest) {
  assertNoActive(tree);
  publishJson(tree, ACTIVE_PATH, { schemaVersion: 1, transaction: manifest.transaction, manifest: manifestPath(manifest.transaction), plan: manifest.plan });
}

function checkRoot(tree, plan) {
  ensure(tree.home === plan.home && equal(tree.handles.get('').info, plan.root), 'Migration belongs to a different DSH_HOME root inode');
  ensure(equal(directoryIdentity(tree.stat('storages')), plan.storage), 'Storage directory inode changed');
  ensure(equal(tree.lock.info, plan.lock), 'Operations lock differs from confirmed plan');
}

function validatePlan(tree, plan, transaction) {
  ensure(object(plan) && plan.schemaVersion === 1 && hash(encodeJson(plan)) === transaction, 'Manifest plan hash mismatch');
  const edge = migration(plan.migration);
  ensure(plan.revision === edge.revision && plan.source?.path === edge.source && plan.inputSchema === edge.inputSchema && plan.outputSchema === edge.outputSchema, 'Unsupported manifest registry version');
  ensure(Array.isArray(plan.directories) && equal(plan.directories.map(entry => entry.path), edge.directories), 'Invalid manifest directory targets');
  checkRoot(tree, plan);
  return edge;
}

function validateTransaction(tree, transaction) {
  const stored = parseJson(tree.read(manifestPath(transaction)).data);
  ensure(object(stored) && stored.schemaVersion === 1 && stored.transaction === transaction && object(stored.plan), 'Invalid migration manifest');
  ensure(['PREPARING', 'ABORTED', 'PREPARED', 'COMMITTED', 'ROLLING_BACK', 'ROLLED_BACK'].includes(stored.status), 'Invalid migration status');
  const edge = validatePlan(tree, stored.plan, transaction);
  if (['PREPARING', 'ABORTED'].includes(stored.status)) return stored;
  const backup = tree.read(backupPath(transaction));
  ensure(backup.sha256 === stored.plan.source.sha256 && backup.data.length === stored.plan.source.bytes && (Number(backup.identity.mode) & 0o777) === 0o400, 'Corrupt or writable source byte snapshot');
  const output = edge.transform(parseJson(backup.data));
  const expectedFiles = output.map(file => ({ path: file.path, before: null, afterSha256: hash(file.data), afterBytes: file.data.length }));
  ensure(equal(expectedFiles, stored.plan.files), 'Manifest target paths or transformation hashes differ from registry');
  ensure(object(stored.directories) && Object.keys(stored.directories).every(relative => edge.directories.includes(relative)), 'Invalid recorded directory identities');
  for (const [index, file] of output.entries()) {
    const copy = tree.read(afterPath(transaction, index));
    ensure(copy.data.equals(file.data) && (Number(copy.identity.mode) & 0o777) === 0o400, `Corrupt or writable target byte snapshot: ${index}`);
  }
  ensure(stored.plan.source.bytes + expectedFiles.reduce((total, file) => total + file.afterBytes * 2, 0) <= MAX_TOTAL, 'Manifest aggregate byte bound exceeded');
  return stored;
}

function verifyDirectories(tree, manifest) {
  for (const entry of manifest.plan.directories) {
    const stat = tree.stat(entry.path, true);
    const expected = manifest.directories[entry.path] ?? entry.before;
    if (stat) {
      ensure(stat.isDirectory(), `Unexpected target directory type: ${entry.path}`);
      if (expected) ensure(equal(directoryIdentity(stat), expected), `Target directory inode changed: ${entry.path}`);
    } else ensure(!expected, `Target directory disappeared: ${entry.path}`);
  }
  const top = manifest.plan.directories[0].path;
  if (tree.stat(top, true)) ensure(tree.entries(top).every(name => name === 'sessions'), 'Unrelated content in migration directory');
  const leaf = manifest.plan.directories[1].path;
  if (tree.stat(leaf, true)) {
    const allowed = new Set(manifest.plan.files.map(file => path.posix.basename(file.path)));
    ensure(tree.entries(leaf).every(name => allowed.has(name)), 'Unrelated content in migrated sessions directory');
  }
}

function verifyTargets(tree, manifest, requireAll = false) {
  checkRoot(tree, manifest.plan);
  tree.assertFile(manifest.plan.source.path, manifest.plan.source);
  verifyDirectories(tree, manifest);
  const current = manifest.plan.files.map((file, index) => {
    const stat = tree.stat(file.path, true);
    const stage = tree.stat(stagePath(manifest.transaction, index), true);
    if (stage) tree.assertFile(stagePath(manifest.transaction, index), { sha256: file.afterSha256 });
    if (!stat) {
      ensure(!requireAll, `Committed target disappeared: ${file.path}`);
      return null;
    }
    const found = tree.read(file.path);
    ensure(found.sha256 === file.afterSha256, `Unrelated concurrent modification: ${file.path}`);
    ensure(!stage, `Target and unpublished stage coexist: ${file.path}`);
    return found;
  });
  return current;
}

function removeActive(tree, transaction) {
  const current = tree.read(ACTIVE_PATH);
  const active = parseJson(current.data);
  ensure(active.schemaVersion === 1 && active.transaction === transaction && active.manifest === manifestPath(transaction), 'Active migration changed');
  tree.sync(`${ROOT}/${transaction}`);
  tree.remove(ACTIVE_PATH, current);
}

function apply(tree, options) {
  const first = buildPlan(tree, options.migration);
  ensure(first.planHash === options.planHash, 'Plan hash mismatch; source bytes, inodes, or target layout changed; plan again');
  const transaction = first.planHash;
  ensure(tree.stat(`${ROOT}/${transaction}`, true) === null, 'Transaction already exists; use recover or rollback, never overwrite snapshots');
  ensureDirectory(tree, 'operations');
  ensureDirectory(tree, ROOT);
  const manifest = { schemaVersion: 1, transaction, status: 'PREPARING', plan: first.plan, directories: {} };
  setActive(tree, manifest);
  try {
    tree.mkdir(`${ROOT}/${transaction}`);
    setManifest(tree, manifest, 'PREPARING');
    tree.writeNew(backupPath(transaction), first.source.data, 0o400);
    for (const [index, file] of first.files.entries()) {
      tree.writeNew(afterPath(transaction, index), file.data, 0o400);
      tree.writeNew(stagePath(transaction, index), file.data);
    }
    checkRoot(tree, first.plan);
    tree.assertFile(first.plan.source.path, first.plan.source);
    ensure(equal(layout(tree, migration(options.migration)), first.plan.directories), 'Target layout changed while preparing snapshots');
    setManifest(tree, manifest, 'PREPARED');
    validateTransaction(tree, transaction);
    for (const entry of first.plan.directories) {
      if (entry.before === null) tree.mkdir(entry.path);
      manifest.directories[entry.path] = directoryIdentity(tree.stat(entry.path));
      setManifest(tree, manifest, 'PREPARED');
    }
    verifyTargets(tree, manifest);
    for (const [index, file] of first.plan.files.entries()) {
      tree.assertFile(first.plan.source.path, first.plan.source);
      verifyDirectories(tree, manifest);
      const stage = tree.read(stagePath(transaction, index));
      ensure(stage.sha256 === file.afterSha256, 'Stage hash mismatch');
      tree.rename(stagePath(transaction, index), file.path, stage, null);
    }
    verifyTargets(tree, manifest, true);
    setManifest(tree, manifest, 'COMMITTED');
    removeActive(tree, transaction);
    return { applied: true, transaction, status: 'COMMITTED', manifest: manifestPath(transaction), files: first.plan.files.map(file => file.path) };
  } catch (error) {
    error.message += `; migration remains gated at ${ACTIVE_PATH}; recover transaction ${transaction}`;
    throw error;
  }
}

function syncTargets(tree, manifest) {
  for (const entry of [...manifest.plan.directories].reverse()) {
    if (tree.stat(entry.path, true)) tree.sync(entry.path);
    const parent = path.posix.dirname(entry.path);
    if (tree.stat(parent, true)) tree.sync(parent);
  }
}

function rollback(tree, manifest, activeExists) {
  if (manifest.status === 'ROLLED_BACK') {
    const current = verifyTargets(tree, manifest);
    ensure(current.every(value => value === null), 'Rolled-back transaction has unexpected target files');
    syncTargets(tree, manifest);
    if (activeExists) removeActive(tree, manifest.transaction);
    return { recovered: true, transaction: manifest.transaction, status: 'ROLLED_BACK' };
  }
  const current = verifyTargets(tree, manifest, manifest.status === 'COMMITTED');
  if (!activeExists) setActive(tree, manifest);
  setManifest(tree, manifest, 'ROLLING_BACK');
  for (const [index, file] of manifest.plan.files.entries()) {
    tree.assertFile(manifest.plan.source.path, manifest.plan.source);
    verifyDirectories(tree, manifest);
    if (current[index]) tree.remove(file.path, current[index]);
  }
  ensure(verifyTargets(tree, manifest).every(value => value === null), 'Rollback targets are not absent');
  syncTargets(tree, manifest);
  setManifest(tree, manifest, 'ROLLED_BACK');
  removeActive(tree, manifest.transaction);
  return { recovered: true, transaction: manifest.transaction, status: 'ROLLED_BACK', sourceRestoredBy: 'Original source bytes retained in place and verified against immutable snapshot', retainedSnapshots: `${ROOT}/${manifest.transaction}` };
}

function abortPreparation(tree, manifest, activeExists) {
  const edge = validatePlan(tree, manifest.plan, manifest.transaction);
  tree.assertFile(edge.source, manifest.plan.source);
  ensure(equal(layout(tree, edge), manifest.plan.directories), 'Unexpected target changes during preparation; refusing recovery');
  ensureDirectory(tree, `${ROOT}/${manifest.transaction}`);
  setManifest(tree, manifest, 'ABORTED');
  if (activeExists) removeActive(tree, manifest.transaction);
  return { recovered: true, transaction: manifest.transaction, status: 'ABORTED', retainedSnapshots: `${ROOT}/${manifest.transaction}`, semantics: 'Preparation interrupted before any target mutation; retain partial snapshots and plan again' };
}

function recover(tree, options) {
  ensure(ID.test(options.transaction ?? ''), 'Expected transaction SHA256');
  const activeInfo = tree.stat(ACTIVE_PATH, true);
  let active;
  if (activeInfo) {
    active = parseJson(tree.read(ACTIVE_PATH).data);
    ensure(active.schemaVersion === 1 && active.transaction === options.transaction && active.manifest === manifestPath(options.transaction), 'Different or malformed active migration; refusing recovery');
    validatePlan(tree, active.plan, options.transaction);
  }
  const present = tree.stat(manifestPath(options.transaction), true);
  ensure(present || active, 'No migration manifest or active preparation exists');
  const manifest = present ? validateTransaction(tree, options.transaction) : { schemaVersion: 1, transaction: options.transaction, status: 'PREPARING', plan: active.plan, directories: {} };
  if (options.action === 'recover' && ['PREPARING', 'ABORTED'].includes(manifest.status)) return abortPreparation(tree, manifest, activeInfo !== null);
  if (options.action === 'rollback') {
    ensure(activeInfo === null, 'Incomplete active migration; use recover first');
    ensure(manifest.status === 'COMMITTED', 'rollback requires a committed transaction');
  } else if (!activeInfo && terminal(manifest.status)) {
    ensure(manifest.status === 'ROLLED_BACK', 'Transaction is committed; use explicit rollback confirmation');
  }
  if (activeInfo && manifest.status === 'COMMITTED' && options.action === 'recover') {
    verifyTargets(tree, manifest, true);
    syncTargets(tree, manifest);
    removeActive(tree, manifest.transaction);
    return { recovered: true, transaction: manifest.transaction, status: 'COMMITTED' };
  }
  return rollback(tree, manifest, activeInfo !== null);
}

export function execute(options, env = process.env) {
  ensure(['plan', 'apply', 'recover', 'rollback'].includes(options.action), 'Expected plan, apply, recover, or rollback');
  if (options.action === 'apply') ensure(ID.test(options.planHash ?? '') && options.confirm === `MIGRATE:${options.planHash}`, 'apply requires exact --plan-hash and --confirm MIGRATE:<hash>');
  if (['recover', 'rollback'].includes(options.action)) ensure(ID.test(options.transaction ?? '') && options.confirm === `${options.action.toUpperCase()}:${options.transaction}`, `${options.action} requires --transaction and exact confirmation`);
  const tree = new SafeTree(options.home);
  try {
    tree.lockExclusive(env.DSH_MIGRATE_FLOCK ?? env.DSH_RETENTION_FLOCK);
    for (const relative of ['storages/.retention-workspace.json', 'storages/.retention-workspace.tmp']) ensure(tree.stat(relative, true) === null, `Incomplete retention journal: ${relative}; recover retention before migration`);
    if (options.action === 'plan') {
      const result = buildPlan(tree, options.migration);
      return { plan: result.plan, planHash: result.planHash, confirmationToken: `MIGRATE:${result.planHash}` };
    }
    if (options.action === 'apply') return apply(tree, options);
    return recover(tree, options);
  } finally { tree.close(); }
}
