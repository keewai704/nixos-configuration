import { constants, lstatSync, realpathSync } from 'node:fs';
import { lstat, mkdir, open } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const checkpointLimits = Object.freeze({ nodes: 32, attempts: 128, promptBytes: 16384, totalPromptBytes: 65536, resultBytes: 8192, maxRuns: 1000, runTimeoutMs: 86400000, nodeTimeoutMs: 1800000 });

function fail(message) { throw new Error(`Checkpoint: ${message}`); }
function object(value, fields) {
  if (!value || Object.getPrototypeOf(value) !== Object.prototype) fail('expected plain JSON object');
  if (Object.keys(value).some(key => !fields.includes(key))) fail('Unknown field');
}
function integer(value, name, min, max) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail(`invalid ${name}`);
  return value;
}
function text(value, name, limit = 256) {
  if (typeof value !== 'string' || !value.trim() || Buffer.byteLength(value) > limit || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) fail(`invalid ${name}`);
  return value;
}
function id(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value)) fail('invalid id');
  return value;
}
function ownerFields(owner) {
  object(owner, ['rootId', 'rootIdentity']);
  return { rootId: text(owner.rootId, 'root owner'), rootIdentity: text(owner.rootIdentity, 'root identity', 1024) };
}
function keyFor(value) { return createHash('sha256').update(id(value)).digest('hex'); }

export function validateGraph(input) {
  object(input, ['nodes', 'maxAttempts', 'nodeTimeoutMs', 'runTimeoutMs']);
  if (!Array.isArray(input.nodes) || input.nodes.length < 1 || input.nodes.length > checkpointLimits.nodes) fail('invalid node count');
  let promptBytes = 0;
  const nodes = input.nodes.map(node => {
    object(node, ['id', 'deps', 'provider', 'model', 'prompt']);
    if (!Array.isArray(node.deps) || node.deps.length > checkpointLimits.nodes) fail('invalid dependencies');
    const deps = node.deps.map(id);
    if (new Set(deps).size !== deps.length) fail('duplicate dependency');
    const prompt = text(node.prompt, 'prompt', checkpointLimits.promptBytes);
    promptBytes += Buffer.byteLength(prompt);
    return { id: id(node.id), deps, provider: text(node.provider, 'provider', 128), model: text(node.model, 'model', 256), prompt };
  });
  if (promptBytes > checkpointLimits.totalPromptBytes) fail('total prompt cap exceeded');
  const ids = new Map(nodes.map(node => [node.id, node]));
  if (ids.size !== nodes.length) fail('duplicate node id');
  const visited = new Set();
  const visiting = new Set();
  function visit(node) {
    if (visiting.has(node.id)) fail('cyclic dependencies');
    if (visited.has(node.id)) return;
    visiting.add(node.id);
    for (const dep of node.deps) {
      if (!ids.has(dep)) fail('unknown dependency');
      visit(ids.get(dep));
    }
    visiting.delete(node.id);
    visited.add(node.id);
  }
  nodes.forEach(visit);
  return {
    nodes,
    maxAttempts: integer(input.maxAttempts ?? nodes.length * 2, 'maxAttempts', nodes.length, checkpointLimits.attempts),
    nodeTimeoutMs: integer(input.nodeTimeoutMs ?? 120000, 'nodeTimeoutMs', 100, checkpointLimits.nodeTimeoutMs),
    runTimeoutMs: integer(input.runTimeoutMs ?? 900000, 'runTimeoutMs', 100, checkpointLimits.runTimeoutMs),
  };
}

function boundedText(value, maxBytes) {
  if (typeof value !== 'string') return '';
  const buffer = Buffer.from(value.slice(0, maxBytes));
  if (buffer.length <= maxBytes) return buffer.toString();
  let end = maxBytes;
  while (end > 0 && (buffer[end] & 0xc0) === 0x80) end -= 1;
  return buffer.subarray(0, end).toString();
}

export function checkpointResult(result) {
  if (!result || !['completed', 'aborted', 'error', 'max-tokens', 'refusal'].includes(result.stopReason) || !Array.isArray(result.output)) fail('invalid subagent result');
  let body = '';
  let truncated = false;
  for (const block of result.output) {
    if (block?.type !== 'text' || typeof block.text !== 'string') { truncated = true; continue; }
    const part = boundedText(block.text, checkpointLimits.resultBytes);
    const next = body ? `${body}\n${part}` : part;
    body = boundedText(next, checkpointLimits.resultBytes);
    if (part.length < block.text.length || Buffer.byteLength(next) > checkpointLimits.resultBytes) truncated = true;
    if (Buffer.byteLength(body) >= checkpointLimits.resultBytes) { truncated ||= result.output.at(-1) !== block; break; }
  }
  return { stopReason: result.stopReason, text: body, truncated, structuredOmitted: result.structured !== undefined };
}

export function retryConfirmation(runId, nodeId, attempt, revision) {
  return `RETRY ${id(runId)}/${id(nodeId)}/${integer(attempt, 'attempt', 1, checkpointLimits.attempts)} @${integer(revision, 'revision', 1, Number.MAX_SAFE_INTEGER)}`;
}

function assertPrivateFile(info, label) {
  if (!info.isFile() || info.uid !== process.getuid() || info.nlink !== 1 || (info.mode & 0o777) !== 0o600) fail(`Unsafe ${label}`);
}
function assertAncestors(path) {
  if (realpathSync(path) !== path) fail('noncanonical or symlinked directory');
  for (let parent = path; ; parent = dirname(parent)) {
    const info = lstatSync(parent);
    if (!info.isDirectory() || (parent !== dirname(parent) && ![0, process.getuid()].includes(info.uid)) || ((info.mode & 0o022) && !(info.uid === 0 && (info.mode & 0o1000)))) fail(`Unsafe ancestor ${parent}`);
    if (parent === dirname(parent)) break;
  }
}

export class CheckpointStore {
  constructor(home, lockExclusive) {
    if (!isAbsolute(home) || resolve(home) !== home || typeof lockExclusive !== 'function') fail('canonical absolute home and OS lock required');
    this.home = home;
    this.root = join(home, 'operations');
    this.path = join(this.root, 'checkpoints.sqlite');
    this.lockRoot = join(this.root, 'checkpoints-locks');
    this.lockExclusive = lockExclusive;
    this.leases = new Map();
    this.acquisitions = new Set();
    this.closed = false;
  }

  async init() {
    if (this.db || this.closed) fail('store already initialized or closed');
    assertAncestors(this.home);
    await mkdir(this.root, { mode: 0o700 }).catch(error => { if (error.code !== 'EEXIST') throw error; });
    assertAncestors(this.root);
    const rootInfo = await lstat(this.root);
    if (rootInfo.uid !== process.getuid() || (rootInfo.mode & 0o777) !== 0o700) fail('Unsafe checkpoint directory');
    await mkdir(this.lockRoot, { mode: 0o700 }).catch(error => { if (error.code !== 'EEXIST') throw error; });
    assertAncestors(this.lockRoot);
    for (const path of [this.root, this.lockRoot]) {
      const info = await lstat(path);
      if (info.uid !== process.getuid() || (info.mode & 0o777) !== 0o700) fail('Unsafe checkpoint directory');
    }
    const file = await open(this.path, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    try { this.dbInfo = await file.stat(); assertPrivateFile(this.dbInfo, 'database'); }
    finally { await file.close(); }
    this.checkFiles();
    try {
      this.db = new DatabaseSync(this.path, { enableForeignKeyConstraints: true, enableDoubleQuotedStringLiterals: false });
      this.db.exec('PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF;');
      this.transaction(() => {
        const version = this.db.prepare('PRAGMA user_version').get().user_version;
        if (version !== 0 && version !== 1) fail('unsupported database version');
        this.db.exec(`
          CREATE TABLE IF NOT EXISTS checkpoint_runs (
            id TEXT PRIMARY KEY, root_id TEXT NOT NULL, root_identity TEXT NOT NULL,
            status TEXT NOT NULL, revision INTEGER NOT NULL, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, deadline_at INTEGER, graph_json TEXT NOT NULL,
            backend TEXT NOT NULL, cwd TEXT NOT NULL, max_attempts INTEGER NOT NULL,
            attempts_started INTEGER NOT NULL DEFAULT 0, owner_token TEXT
          );
          CREATE TABLE IF NOT EXISTS checkpoint_nodes (
            run_id TEXT NOT NULL REFERENCES checkpoint_runs(id), id TEXT NOT NULL,
            status TEXT NOT NULL, attempt INTEGER NOT NULL, PRIMARY KEY(run_id,id)
          );
          CREATE TABLE IF NOT EXISTS checkpoint_attempts (
            run_id TEXT NOT NULL, node_id TEXT NOT NULL, attempt INTEGER NOT NULL,
            status TEXT NOT NULL, child_id TEXT, result_json TEXT, error TEXT,
            started_at INTEGER, finished_at INTEGER,
            PRIMARY KEY(run_id,node_id,attempt),
            FOREIGN KEY(run_id,node_id) REFERENCES checkpoint_nodes(run_id,id)
          );
          CREATE TABLE IF NOT EXISTS checkpoint_actions (
            id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES checkpoint_runs(id),
            root_id TEXT NOT NULL, action TEXT NOT NULL, prior_revision INTEGER,
            at INTEGER NOT NULL, actor TEXT NOT NULL
          );
          CREATE INDEX IF NOT EXISTS checkpoint_owner ON checkpoint_runs(root_id,updated_at);
          CREATE INDEX IF NOT EXISTS checkpoint_actions_run ON checkpoint_actions(run_id,at);
          PRAGMA user_version=1;
        `);
      });
      for (const row of this.db.prepare('SELECT id FROM checkpoint_runs WHERE owner_token IS NOT NULL').all()) await this.recover(row.id);
      return this;
    } catch (error) { await this.close(); throw error; }
  }

  checkFiles() {
    if (this.closed) fail('store closed');
    assertAncestors(this.lockRoot);
    for (const directory of [this.root, this.lockRoot]) {
      const info = lstatSync(directory);
      if (info.uid !== process.getuid() || (info.mode & 0o777) !== 0o700) fail('Unsafe checkpoint directory');
    }
    for (const suffix of ['', '-wal', '-shm', '-journal']) {
      let info;
      try { info = lstatSync(this.path + suffix); }
      catch (error) { if (suffix && error.code === 'ENOENT') continue; throw error; }
      assertPrivateFile(info, `database${suffix}`);
      if (!suffix && (info.ino !== this.dbInfo.ino || info.dev !== this.dbInfo.dev)) fail('database ownership changed');
    }
  }

  transaction(action) {
    this.checkFiles();
    if (!this.db) fail('store not initialized');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const value = action();
      this.checkFiles();
      this.db.exec('COMMIT');
      return value;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  row(runId, owner, revision) {
    const row = this.db.prepare('SELECT * FROM checkpoint_runs WHERE id=?').get(id(runId));
    if (!row) fail('run not found');
    if (owner) {
      const who = ownerFields(owner);
      if (row.root_id !== who.rootId || row.root_identity !== who.rootIdentity) fail('root owner mismatch');
    }
    if (revision !== undefined && row.revision !== integer(revision, 'revision', 1, Number.MAX_SAFE_INTEGER)) fail('revision changed; refresh status');
    return row;
  }

  audit(runId, owner, action, priorRevision, authorization) {
    if (authorization === undefined) return;
    object(authorization, ['actor', 'rootId', 'action']);
    if (!['authenticated-operator', 'agent-approved'].includes(authorization.actor) || authorization.rootId !== owner.rootId || authorization.action !== action) fail('invalid audit authorization');
    if (this.db.prepare('SELECT COUNT(*) AS count FROM checkpoint_actions WHERE run_id=?').get(runId).count >= 1024 || this.db.prepare('SELECT COUNT(*) AS count FROM checkpoint_actions').get().count >= 100000) fail('action audit cap reached');
    this.db.prepare('INSERT INTO checkpoint_actions VALUES(?,?,?,?,?,?,?)').run(randomUUID(), runId, owner.rootId, action, priorRevision, Date.now(), authorization.actor);
  }

  actions(runId, owner) {
    return this.transaction(() => {
      this.row(runId, owner);
      return this.db.prepare('SELECT id,root_id AS rootId,action,prior_revision AS priorRevision,at,actor FROM checkpoint_actions WHERE run_id=? ORDER BY at,rowid').all(runId).map(row => ({ ...row }));
    });
  }

  create({ id: runId = randomUUID(), owner, graph, backend = 'spawn', cwd }, authorize = () => {}) {
    id(runId);
    const who = ownerFields(owner);
    const spec = validateGraph(graph);
    text(backend, 'backend', 128);
    if (!isAbsolute(cwd) || resolve(cwd) !== cwd || realpathSync(cwd) !== cwd || !lstatSync(cwd).isDirectory()) fail('cwd must be an existing canonical directory');
    this.transaction(() => {
      const authorization = authorize();
      if (this.db.prepare('SELECT COUNT(*) AS count FROM checkpoint_runs').get().count >= checkpointLimits.maxRuns) fail('run count cap reached; offline retention required');
      const now = Date.now();
      this.db.prepare('INSERT INTO checkpoint_runs(id,root_id,root_identity,status,revision,created_at,updated_at,graph_json,backend,cwd,max_attempts) VALUES(?,?,?,?,?,?,?,?,?,?,?)')
        .run(runId, who.rootId, who.rootIdentity, 'draft', 1, now, now, JSON.stringify(spec), backend, cwd, spec.maxAttempts);
      for (const node of spec.nodes) {
        this.db.prepare('INSERT INTO checkpoint_nodes VALUES(?,?,?,?)').run(runId, node.id, 'pending', 1);
        this.db.prepare('INSERT INTO checkpoint_attempts(run_id,node_id,attempt,status) VALUES(?,?,?,?)').run(runId, node.id, 1, 'pending');
      }
      this.audit(runId, who, 'create', null, authorization);
    });
    return this.snapshot(runId, who);
  }

  snapshot(runId, owner, outputNodeId) {
    return this.transaction(() => this.view(this.row(runId, owner), outputNodeId));
  }

  view(row, outputNodeId) {
    const graph = JSON.parse(row.graph_json);
    const nodes = this.db.prepare('SELECT * FROM checkpoint_nodes WHERE run_id=? ORDER BY rowid').all(row.id).map(node => {
      const attempts = this.db.prepare('SELECT attempt,status,child_id,started_at,finished_at,error,result_json FROM checkpoint_attempts WHERE run_id=? AND node_id=? ORDER BY attempt').all(row.id, node.id);
      const latest = attempts.at(-1);
      const spec = graph.nodes.find(item => item.id === node.id);
      return {
        id: node.id, deps: spec.deps, provider: spec.provider, model: spec.model, promptPreview: boundedText(spec.prompt, 256), status: node.status, attempt: node.attempt,
        ...(node.id === outputNodeId ? { prompt: spec.prompt } : {}),
        attempts: attempts.map(item => ({ attempt: item.attempt, status: item.status, childId: item.child_id, startedAt: item.started_at, finishedAt: item.finished_at, error: item.error })),
        ...(node.id === outputNodeId && latest.result_json ? { result: JSON.parse(latest.result_json) } : {}),
        ...(['ambiguous', 'failed'].includes(node.status) ? { retryConfirmation: retryConfirmation(row.id, node.id, node.attempt, row.revision) } : {}),
      };
    });
    return { id: row.id, rootId: row.root_id, status: row.status, revision: row.revision, createdAt: row.created_at, updatedAt: row.updated_at, deadlineAt: row.deadline_at, backend: row.backend, cwd: row.cwd, maxAttempts: row.max_attempts, attemptsStarted: row.attempts_started, nodeTimeoutMs: graph.nodeTimeoutMs, runTimeoutMs: graph.runTimeoutMs, nodes };
  }

  list(owner) {
    return this.transaction(() => {
      const rows = owner ? this.db.prepare('SELECT * FROM checkpoint_runs WHERE root_id=? AND root_identity=? ORDER BY updated_at DESC LIMIT 100').all(ownerFields(owner).rootId, owner.rootIdentity)
        : this.db.prepare('SELECT * FROM checkpoint_runs ORDER BY updated_at DESC LIMIT 100').all();
      return rows.map(row => ({ id: row.id, rootId: row.root_id, status: row.status, revision: row.revision, createdAt: row.created_at, updatedAt: row.updated_at, deadlineAt: row.deadline_at, attemptsStarted: row.attempts_started, maxAttempts: row.max_attempts }));
    });
  }

  async acquire(runId) {
    const task = this.acquireFile(runId);
    this.acquisitions.add(task);
    try { return await task; } finally { this.acquisitions.delete(task); }
  }

  async acquireFile(runId) {
    this.checkFiles();
    const path = join(this.lockRoot, `${keyFor(runId)}.lock`);
    const file = await open(path, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    try {
      const info = await file.stat();
      assertPrivateFile(info, 'lease');
      await this.lockExclusive(file.fd);
      const current = await lstat(path);
      if (info.dev !== current.dev || info.ino !== current.ino) fail('lease ownership changed');
      this.checkFiles();
      const lease = { id: runId, token: randomUUID(), file, info, path, released: false };
      this.leases.set(lease.token, lease);
      return lease;
    } catch (error) { await file.close(); throw error; }
  }

  assertLease(lease, owned = true) {
    if (this.leases.get(lease.token) !== lease || lease.released) fail('lease not owned');
    const info = lstatSync(lease.path);
    assertPrivateFile(info, 'lease');
    if (info.ino !== lease.info.ino || info.dev !== lease.info.dev) fail('lease ownership changed');
    const row = this.row(lease.id);
    if (owned && row.owner_token !== lease.token) fail('lease owner token changed');
    return row;
  }

  update(row, fields = {}) {
    const next = { status: row.status, owner_token: row.owner_token, deadline_at: row.deadline_at, ...fields };
    const changed = this.db.prepare('UPDATE checkpoint_runs SET status=?,owner_token=?,deadline_at=?,updated_at=?,revision=revision+1 WHERE id=? AND revision=?')
      .run(next.status, next.owner_token, next.deadline_at, Date.now(), row.id, row.revision);
    if (changed.changes !== 1) fail('revision compare-and-swap failed');
  }

  state(runId) {
    const statuses = this.db.prepare('SELECT status FROM checkpoint_nodes WHERE run_id=?').all(runId).map(node => node.status);
    return statuses.includes('ambiguous') ? 'ambiguous' : statuses.includes('failed') ? 'failed' : statuses.every(status => status === 'completed') ? 'completed' : 'paused';
  }

  recoverOwned(row) {
    if (!row.owner_token) return false;
    this.db.prepare("UPDATE checkpoint_attempts SET status='ambiguous',error='Ownership lost; effects and costs may have occurred',finished_at=? WHERE run_id=? AND status='running'").run(Date.now(), row.id);
    this.db.prepare("UPDATE checkpoint_nodes SET status='ambiguous' WHERE run_id=? AND status='running'").run(row.id);
    this.update(row, { owner_token: null, status: row.status === 'cancelled' ? 'cancelled' : this.state(row.id) });
    return true;
  }

  async recover(runId) {
    let lease;
    try { lease = await this.acquire(runId); }
    catch (error) { if (['EAGAIN', 'EWOULDBLOCK'].includes(error.code)) return false; throw error; }
    try { return this.transaction(() => this.recoverOwned(this.assertLease(lease, false))); }
    finally { await this.closeLease(lease); }
  }

  async claim(runId, owner, revision, action, authorize = () => {}) {
    if (!['start', 'resume'].includes(action)) fail('invalid run action');
    this.snapshot(runId, owner);
    let lease;
    try { lease = await this.acquire(runId); }
    catch (error) { if (['EAGAIN', 'EWOULDBLOCK'].includes(error.code)) fail('run is owned by an active process'); throw error; }
    try {
      const recovered = this.transaction(() => {
        authorize();
        this.assertLease(lease, false);
        return this.recoverOwned(this.row(runId, owner));
      });
      if (recovered) fail('ownership lost; refresh revision and confirm again');
      this.transaction(() => {
        const authorization = authorize();
        this.assertLease(lease, false);
        const row = this.row(runId, owner, revision);
        if (row.owner_token) fail('run already owned');
        if (action === 'start' ? row.status !== 'draft' : !['paused', 'ambiguous', 'failed'].includes(row.status)) fail(`cannot ${action} run in ${row.status} state`);
        const deadline = row.deadline_at ?? Date.now() + JSON.parse(row.graph_json).runTimeoutMs;
        if (deadline <= Date.now()) fail('run deadline expired; no more dispatch');
        this.update(row, { owner_token: lease.token, status: 'running', deadline_at: deadline });
        this.audit(row.id, owner, action, revision, authorization);
      });
      return lease;
    } catch (error) { await this.closeLease(lease); throw error; }
  }

  ready(lease) {
    return this.transaction(() => {
      const row = this.assertLease(lease);
      if (row.status !== 'running' || row.deadline_at <= Date.now() || row.attempts_started >= row.max_attempts) return null;
      const graph = JSON.parse(row.graph_json);
      const nodes = new Map(this.db.prepare('SELECT id,status FROM checkpoint_nodes WHERE run_id=?').all(row.id).map(node => [node.id, node.status]));
      const node = graph.nodes.find(item => nodes.get(item.id) === 'pending' && item.deps.every(dep => nodes.get(dep) === 'completed'));
      return node ? { node, cwd: row.cwd, backend: row.backend, deadlineAt: Math.min(row.deadline_at, Date.now() + graph.nodeTimeoutMs) } : null;
    });
  }

  dispatch(lease, childId = null, authorize = () => {}) {
    return this.transaction(() => {
      const row = this.assertLease(lease);
      if (row.status !== 'running' || row.deadline_at <= Date.now()) return null;
      const graph = JSON.parse(row.graph_json);
      const states = new Map(this.db.prepare('SELECT * FROM checkpoint_nodes WHERE run_id=?').all(row.id).map(node => [node.id, node]));
      if ([...states.values()].some(node => node.status === 'running')) fail('only one node may run at once');
      const node = graph.nodes.find(item => states.get(item.id).status === 'pending' && item.deps.every(dep => states.get(dep).status === 'completed'));
      if (!node || row.attempts_started >= row.max_attempts) return null;
      authorize(node);
      const attempt = states.get(node.id).attempt;
      const dependencies = node.deps.map(dep => {
        const result = this.db.prepare('SELECT result_json FROM checkpoint_attempts WHERE run_id=? AND node_id=? AND attempt=?').get(row.id, dep, states.get(dep).attempt);
        if (!result?.result_json) fail('completed dependency lacks output');
        return { id: dep, result: JSON.parse(result.result_json) };
      });
      const now = Date.now();
      if (childId !== null) text(childId, 'child id');
      const changed = this.db.prepare("UPDATE checkpoint_attempts SET status='running',child_id=?,started_at=? WHERE run_id=? AND node_id=? AND attempt=? AND status='pending'").run(childId, now, row.id, node.id, attempt);
      if (changed.changes !== 1) fail('attempt compare-and-swap failed');
      this.db.prepare("UPDATE checkpoint_nodes SET status='running' WHERE run_id=? AND id=? AND status='pending'").run(row.id, node.id);
      this.db.prepare('UPDATE checkpoint_runs SET attempts_started=attempts_started+1 WHERE id=?').run(row.id);
      this.update(row);
      return { node, attempt, childId, dependencies, backend: row.backend, cwd: row.cwd, deadlineAt: Math.min(row.deadline_at, now + graph.nodeTimeoutMs) };
    });
  }

  child(lease, nodeId, attempt, childId) {
    this.transaction(() => {
      const row = this.assertLease(lease);
      const changed = this.db.prepare("UPDATE checkpoint_attempts SET child_id=? WHERE run_id=? AND node_id=? AND attempt=? AND status='running' AND (child_id IS NULL OR child_id=?)")
        .run(text(childId, 'child id'), row.id, id(nodeId), attempt, childId);
      if (changed.changes !== 1) fail('child identity compare-and-swap failed');
      this.update(row);
    });
  }

  finishAttempt(lease, nodeId, attempt, status, result, error) {
    this.transaction(() => {
      const row = this.assertLease(lease);
      const changed = this.db.prepare("UPDATE checkpoint_attempts SET status=?,result_json=?,error=?,finished_at=? WHERE run_id=? AND node_id=? AND attempt=? AND status='running'")
        .run(status, result ? JSON.stringify(result) : null, error ? boundedText(error, 1024) : null, Date.now(), row.id, id(nodeId), integer(attempt, 'attempt', 1, checkpointLimits.attempts));
      if (changed.changes !== 1) fail('attempt settlement compare-and-swap failed');
      this.db.prepare("UPDATE checkpoint_nodes SET status=? WHERE run_id=? AND id=? AND attempt=? AND status='running'").run(status, row.id, nodeId, attempt);
      this.update(row);
    });
  }

  settle(lease, nodeId, attempt, result) {
    const saved = checkpointResult(result);
    this.finishAttempt(lease, nodeId, attempt, saved.stopReason === 'completed' ? 'completed' : 'failed', saved, null);
  }

  ambiguous(lease, nodeId, attempt, reason) { this.finishAttempt(lease, nodeId, attempt, 'ambiguous', null, String(reason)); }

  async release(lease) {
    if (lease.released) return;
    try {
      this.transaction(() => {
        const row = this.assertLease(lease);
        this.db.prepare("UPDATE checkpoint_attempts SET status='ambiguous',error='Execution ended without captured result',finished_at=? WHERE run_id=? AND status='running'").run(Date.now(), row.id);
        this.db.prepare("UPDATE checkpoint_nodes SET status='ambiguous' WHERE run_id=? AND status='running'").run(row.id);
        this.update(row, { owner_token: null, status: row.status === 'cancelled' ? 'cancelled' : row.deadline_at <= Date.now() && this.state(row.id) === 'paused' ? 'expired' : this.state(row.id) });
      });
    } finally { await this.closeLease(lease); }
  }

  async closeLease(lease) {
    if (lease.released) return;
    lease.released = true;
    this.leases.delete(lease.token);
    await lease.file.close();
  }

  async retry({ id: runId, owner, nodeId, attempt, revision, confirmation }, authorize = () => {}) {
    if (confirmation !== retryConfirmation(runId, nodeId, attempt, revision)) fail('explicit retry confirmation required');
    this.snapshot(runId, owner);
    const lease = await this.acquire(runId);
    try {
      const recovered = this.transaction(() => {
        authorize();
        this.assertLease(lease, false);
        return this.recoverOwned(this.row(runId, owner));
      });
      if (recovered) fail('ownership lost; refresh revision');
      this.transaction(() => {
        const authorization = authorize();
        this.assertLease(lease, false);
        const row = this.row(runId, owner, revision);
        if (row.owner_token || !['ambiguous', 'failed', 'paused'].includes(row.status)) fail('run cannot retry');
        if (row.deadline_at <= Date.now() || row.attempts_started >= row.max_attempts) fail('run deadline or attempt cap reached');
        const node = this.db.prepare('SELECT * FROM checkpoint_nodes WHERE run_id=? AND id=?').get(row.id, id(nodeId));
        if (!node || node.attempt !== attempt || !['ambiguous', 'failed'].includes(node.status)) fail('attempt changed or not retryable');
        this.db.prepare('INSERT INTO checkpoint_attempts(run_id,node_id,attempt,status) VALUES(?,?,?,?)').run(row.id, nodeId, attempt + 1, 'pending');
        this.db.prepare("UPDATE checkpoint_nodes SET status='pending',attempt=attempt+1 WHERE run_id=? AND id=? AND attempt=?").run(row.id, nodeId, attempt);
        this.update(row, { status: this.state(row.id) });
        this.audit(row.id, owner, 'retry', revision, authorization);
      });
    } finally { await this.closeLease(lease); }
    return this.snapshot(runId, owner);
  }

  async cancel(runId, owner, revision, activeLease, authorize = () => {}) {
    this.snapshot(runId, owner);
    const lease = activeLease ?? await this.acquire(runId);
    try {
      this.transaction(() => {
        const authorization = authorize();
        this.assertLease(lease, false);
        const row = this.row(runId, owner, revision);
        if (activeLease) this.assertLease(activeLease);
        if (row.status === 'completed') fail('completed run cannot cancel');
        if (!activeLease && row.owner_token) {
          this.db.prepare("UPDATE checkpoint_attempts SET status='ambiguous',error='Ownership lost before cancellation',finished_at=? WHERE run_id=? AND status='running'").run(Date.now(), row.id);
          this.db.prepare("UPDATE checkpoint_nodes SET status='ambiguous' WHERE run_id=? AND status='running'").run(row.id);
        }
        this.update(row, { status: 'cancelled', ...activeLease ? {} : { owner_token: null } });
        this.audit(row.id, owner, 'cancel', revision, authorization);
      });
    } finally { if (!activeLease) await this.closeLease(lease); }
    return this.snapshot(runId, owner);
  }

  async close() {
    if (this.closePromise) return this.closePromise;
    this.closed = true;
    this.closePromise = (async () => {
      await Promise.allSettled(this.acquisitions);
      for (const lease of this.leases.values()) await this.closeLease(lease);
      this.db?.close();
      this.db = undefined;
    })();
    return this.closePromise;
  }
}
