import { DatabaseSync } from 'node:sqlite';
import { constants, closeSync, fstatSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';

export class BudgetError extends Error {
  constructor(message, code = 'BUDGET_REFUSED') { super(message); this.name = 'BudgetError'; this.code = code; this.status = 409; }
}

const keys = ['maxRequests', 'maxChildren', 'maxConcurrentChildren', 'maxOutputTokens', 'maxCostMicros', 'deadlineAt'];
const validCount = value => Number.isSafeInteger(value) && value >= 0;
const need = (condition, message) => { if (!condition) throw new BudgetError(message); };
const identifier = value => { need(typeof value === 'string' && value.length > 0 && value.length <= 1024 && !/[\u0000-\u001f\u007f]/.test(value), 'Invalid budget identity'); return value; };
const sum = values => { const result = values.reduce((a, b) => a + b, 0); need(validCount(result), 'Budget accounting overflow'); return result; };
const object = value => value && typeof value === 'object' && !Array.isArray(value);

export function validateLimits(value = {}) {
  need(object(value) && Object.keys(value).every(key => keys.includes(key)), 'Unknown budget limit');
  const result = {};
  for (const key of keys) if (value[key] !== undefined) { need(validCount(value[key]), `Invalid budget ${key}`); result[key] = value[key]; }
  return result;
}

function validatePricing(value) {
  if (value === undefined || value === null) return undefined;
  need(object(value) && Object.keys(value).length === 4 && ['input', 'output', 'cacheRead', 'cacheWrite'].every(key => validCount(value[key])), 'Invalid integer per-million pricing');
  return { input: value.input, output: value.output, cacheRead: value.cacheRead, cacheWrite: value.cacheWrite };
}

function normalizedUsage(value) {
  if (!object(value)) return undefined;
  const fields = ['inputTokens', 'outputTokens', 'cacheReadTokens', 'cacheWriteTokens', 'reasoningTokens', 'totalTokens'];
  if (fields.some(key => value[key] !== undefined && !validCount(value[key]))) return undefined;
  if (value.reasoningTokens !== undefined && (!validCount(value.outputTokens) || value.reasoningTokens > value.outputTokens)) return undefined;
  const result = Object.fromEntries(fields.filter(key => value[key] !== undefined).map(key => [key, value[key]]));
  const full = ['inputTokens', 'outputTokens', 'cacheReadTokens', 'cacheWriteTokens'].every(key => validCount(result[key]));
  if (full && result.totalTokens !== undefined && sum([result.inputTokens, result.outputTokens, result.cacheReadTokens, result.cacheWriteTokens]) !== result.totalTokens) return undefined;
  return result;
}

export function priceUsage(usage, pricing) {
  const valid = normalizedUsage(usage);
  const rates = validatePricing(pricing);
  if (!rates || !valid || !['inputTokens', 'outputTokens', 'cacheReadTokens', 'cacheWriteTokens'].every(key => validCount(valid[key]))) return null;
  const numerator = BigInt(valid.inputTokens) * BigInt(rates.input) + BigInt(valid.outputTokens) * BigInt(rates.output)
    + BigInt(valid.cacheReadTokens) * BigInt(rates.cacheRead) + BigInt(valid.cacheWriteTokens) * BigInt(rates.cacheWrite);
  const amount = Number((numerator + 999999n) / 1000000n);
  need(validCount(amount), 'Budget price overflow');
  return amount;
}

function processStamp(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, 'utf8');
    const start = stat.slice(stat.lastIndexOf(')') + 2).split(' ')[19];
    return `${readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim()}:${start}`;
  } catch (error) { if (error.code === 'ENOENT' || error.code === 'ESRCH') return null; throw error; }
}

function safeDatabase(path) {
  need(process.platform === 'linux', 'Budget persistence requires Linux process identities');
  const absolute = resolve(path);
  mkdirSync(dirname(absolute), { recursive: true, mode: 0o700 });
  need(realpathSync(dirname(absolute)) === dirname(absolute), 'Unsafe symlink budget directory');
  for (let dir = dirname(absolute); ; dir = dirname(dir)) {
    const info = lstatSync(dir);
    need(info.isDirectory() && (dir === dirname(dir) || [0, process.getuid()].includes(info.uid))
      && (!(info.mode & 0o022) || (info.uid === 0 && (info.mode & 0o1000))), 'Unsafe budget directory');
    if (dir === dirname(dir)) break;
  }
  need(lstatSync(dirname(absolute)).uid === process.getuid(), 'Budget directory must be owned by the current user');
  for (const suffix of ['', '-wal', '-shm', '-journal']) {
    try {
      const info = lstatSync(`${absolute}${suffix}`);
      need(info.isFile() && info.nlink === 1 && info.uid === process.getuid() && !(info.mode & 0o077), 'Unsafe budget database or SQLite sidecar');
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const fd = openSync(absolute, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
  try {
    const info = fstatSync(fd);
    const current = lstatSync(absolute);
    need(info.isFile() && info.nlink === 1 && info.uid === process.getuid() && !(info.mode & 0o077)
      && current.ino === info.ino && current.dev === info.dev, 'Unsafe budget database');
  } finally { closeSync(fd); }
  return absolute;
}

export class BudgetLedger {
  constructor(path, { now = Date.now } = {}) {
    this.now = now;
    this.owner = randomUUID();
    this.closed = false;
    this.db = new DatabaseSync(safeDatabase(path), { enableForeignKeyConstraints: true, enableDoubleQuotedStringLiterals: false });
    try {
      this.db.exec('PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;');
      const version = this.db.prepare('PRAGMA user_version').get().user_version;
      need(version === 0 || version === 1, 'Unsupported budget schema version');
      if (version === 0) {
        need(this.db.prepare("SELECT count(*) n FROM sqlite_master WHERE type='table'").get().n === 0, 'Unversioned budget database is not empty');
        this.db.exec(`BEGIN IMMEDIATE;
          CREATE TABLE budget_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE budget_owners (id TEXT PRIMARY KEY, pid INTEGER NOT NULL, start TEXT NOT NULL, closed INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE budget_roots (id TEXT PRIMARY KEY, limits_json TEXT NOT NULL, revision INTEGER NOT NULL);
          CREATE TABLE budget_sessions (id TEXT PRIMARY KEY, created_at INTEGER, parent_id TEXT, root_id TEXT NOT NULL REFERENCES budget_roots(id));
          CREATE TABLE budget_requests (id TEXT PRIMARY KEY, root_id TEXT NOT NULL REFERENCES budget_roots(id), session_id TEXT NOT NULL REFERENCES budget_sessions(id), owner_id TEXT NOT NULL REFERENCES budget_owners(id), provider TEXT NOT NULL, model TEXT NOT NULL, purpose TEXT NOT NULL, state TEXT NOT NULL, output_reserved INTEGER NOT NULL, input_upper INTEGER, cost_reserved INTEGER NOT NULL, pricing_json TEXT, usage_json TEXT, cost_micros INTEGER, settlement_json TEXT);
          CREATE INDEX budget_requests_root ON budget_requests(root_id);
          CREATE TABLE budget_children (id TEXT PRIMARY KEY, root_id TEXT NOT NULL REFERENCES budget_roots(id), parent_id TEXT NOT NULL REFERENCES budget_sessions(id), child_id TEXT NOT NULL, owner_id TEXT NOT NULL REFERENCES budget_owners(id), kind TEXT NOT NULL, provider TEXT NOT NULL, state TEXT NOT NULL);
          CREATE INDEX budget_children_root ON budget_children(root_id);
          INSERT INTO budget_meta VALUES ('format', 'dsh-budget-v1');
          PRAGMA user_version=1;
          COMMIT;`);
      }
      need(this.db.prepare("SELECT value FROM budget_meta WHERE key='format'").get()?.value === 'dsh-budget-v1', 'Unsupported budget database');
      this.transaction(() => {
        for (const owner of this.db.prepare('SELECT * FROM budget_owners WHERE closed=0').all()) {
          let stamp;
          try { stamp = processStamp(owner.pid); } catch { continue; }
          if (stamp !== owner.start) this.orphanOwner(owner.id);
        }
        this.db.prepare('INSERT INTO budget_owners(id,pid,start) VALUES(?,?,?)').run(this.owner, process.pid, processStamp(process.pid));
      });
    } catch (error) { this.db.close(); throw error; }
  }

  transaction(action) {
    need(!this.closed, 'Budget ledger is closed');
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = action(); this.db.exec('COMMIT'); return result; }
    catch (error) { try { this.db.exec('ROLLBACK'); } catch {} throw error; }
  }

  orphanOwner(id) {
    this.db.prepare("UPDATE budget_requests SET state='ambiguous' WHERE owner_id=? AND state IN ('reserved','dispatched')").run(id);
    this.db.prepare("UPDATE budget_children SET state='ambiguous' WHERE owner_id=? AND state IN ('reserved','published')").run(id);
    this.db.prepare('UPDATE budget_owners SET closed=1 WHERE id=?').run(id);
  }

  bindSession({ id, createdAt, parentId }, limits = {}) {
    identifier(id); if (parentId !== undefined) identifier(parentId);
    need(validCount(createdAt), 'Invalid session identity timestamp');
    const policy = validateLimits(limits);
    return this.transaction(() => {
      const existing = this.db.prepare('SELECT * FROM budget_sessions WHERE id=?').get(id);
      if (existing) {
        need((existing.created_at === null || existing.created_at === createdAt) && existing.parent_id === (parentId ?? null), 'Budget session identity conflict');
        if (existing.created_at === null) this.db.prepare('UPDATE budget_sessions SET created_at=? WHERE id=?').run(createdAt, id);
        return existing.root_id;
      }
      const root = parentId === undefined ? id : this.rootFor(parentId);
      if (parentId === undefined) this.db.prepare('INSERT INTO budget_roots VALUES(?,?,1)').run(id, JSON.stringify(policy));
      this.db.prepare('INSERT INTO budget_sessions VALUES(?,?,?,?)').run(id, createdAt, parentId ?? null, root);
      return root;
    });
  }

  rootFor(sessionId) {
    need(!this.closed, 'Budget ledger is closed');
    const row = this.db.prepare('SELECT root_id FROM budget_sessions WHERE id=?').get(identifier(sessionId));
    need(row, 'Budget lineage unavailable; restore the durable parent lineage before dispatch');
    return row.root_id;
  }

  configure({ rootSessionId, revision, limits, confirmation }) {
    const policy = validateLimits(limits);
    need(confirmation === `BUDGET ${rootSessionId} ${revision}`, 'Explicit budget confirmation required');
    return this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_roots WHERE id=?').get(identifier(rootSessionId));
      need(row && row.revision === revision, 'Budget configuration revision changed');
      const state = this.snapshot(rootSessionId);
      need(state.activeChildren === 0 && !state.requestRecords.some(request => ['reserved', 'dispatched'].includes(request.state)), 'Budget changes require a quiescent root without outstanding work');
      need(validCount(revision + 1), 'Budget revision overflow');
      this.db.prepare('UPDATE budget_roots SET limits_json=?,revision=revision+1 WHERE id=?').run(JSON.stringify(policy), rootSessionId);
      return this.snapshot(rootSessionId);
    });
  }

  snapshot(sessionId) {
    const rootId = this.rootFor(sessionId);
    const root = this.db.prepare('SELECT * FROM budget_roots WHERE id=?').get(rootId);
    const requests = this.db.prepare('SELECT * FROM budget_requests WHERE root_id=?').all(rootId);
    const children = this.db.prepare('SELECT * FROM budget_children WHERE root_id=?').all(rootId);
    const uncertain = requests.filter(row => ['reserved', 'dispatched', 'ambiguous'].includes(row.state));
    const measured = requests.filter(row => row.state === 'measured');
    const usages = measured.map(row => JSON.parse(row.usage_json));
    const unknownCostRequests = requests.filter(row => row.state !== 'cancelled' && row.cost_micros === null).length;
    return {
      rootSessionId: rootId, revision: root.revision, limits: JSON.parse(root.limits_json),
      requests: requests.filter(row => row.state !== 'cancelled').length, children: children.length,
      activeChildren: children.filter(row => row.state !== 'settled').length,
      ambiguousChildren: children.filter(row => row.state === 'ambiguous').length,
      ambiguousRequests: requests.filter(row => row.state === 'ambiguous').length, unknownCostRequests,
      reserved: { outputTokens: sum(uncertain.map(row => row.output_reserved)), costMicros: sum(uncertain.map(row => row.cost_reserved)) },
      usage: { outputTokens: sum(usages.map(row => row.outputTokens ?? 0)), costMicros: unknownCostRequests ? null : sum(measured.map(row => row.cost_micros ?? 0)) },
      accountedOutputTokens: sum([...usages.map(row => row.outputTokens ?? 0), ...requests.filter(row => row.state === 'charged').map(row => row.output_reserved)]),
      accountedCostMicros: sum([...measured.map(row => row.cost_micros ?? 0), ...requests.filter(row => row.state === 'charged').map(row => row.cost_reserved)]),
      requestRecords: requests.map(({ owner_id, pricing_json, settlement_json, ...row }) => ({ ...row, usage: row.usage_json === null ? null : JSON.parse(row.usage_json), usage_json: undefined })),
      childRecords: children.map(({ owner_id, ...row }) => row),
    };
  }

  reconcile({ rootSessionId, revision, requestIds = [], childIds = [], confirmation }) {
    need(Array.isArray(requestIds) && Array.isArray(childIds) && requestIds.length + childIds.length > 0
      && requestIds.length + childIds.length <= 100 && new Set(requestIds).size === requestIds.length
      && new Set(childIds).size === childIds.length, 'Invalid budget reconciliation selection');
    requestIds.forEach(identifier); childIds.forEach(identifier);
    const token = `RECONCILE ${rootSessionId} ${revision} ${[...requestIds].sort().join(',')} ${[...childIds].sort().join(',')}`;
    need(confirmation === token, 'Explicit confirmation of quiescence and full reservation charge is required');
    return this.transaction(() => {
      const root = this.db.prepare('SELECT * FROM budget_roots WHERE id=?').get(identifier(rootSessionId));
      need(root && root.revision === revision, 'Budget reconciliation revision changed');
      for (const id of requestIds) {
        const row = this.db.prepare('SELECT * FROM budget_requests WHERE id=?').get(id);
        need(row?.root_id === rootSessionId && row.state === 'ambiguous', 'Only ambiguous requests in this root can be reconciled');
        const usage = row.usage_json === null ? undefined : normalizedUsage(JSON.parse(row.usage_json));
        need(!usage || !validCount(usage.outputTokens) || usage.outputTokens <= row.output_reserved, 'Observed output exceeded the reservation; cannot reconcile to a smaller charge');
        if (row.input_upper !== null && usage && ['inputTokens', 'cacheReadTokens', 'cacheWriteTokens'].every(key => validCount(usage[key]))) {
          need(sum([usage.inputTokens, usage.cacheReadTokens, usage.cacheWriteTokens]) <= row.input_upper, 'Observed input exceeded the configured billing bound');
        }
        this.db.prepare("UPDATE budget_requests SET state='charged' WHERE id=?").run(id);
      }
      for (const id of childIds) {
        const row = this.db.prepare('SELECT * FROM budget_children WHERE id=?').get(id);
        need(row?.root_id === rootSessionId && row.state === 'ambiguous', 'Only ambiguous children in this root can be reconciled');
        this.db.prepare("UPDATE budget_children SET state='settled' WHERE id=?").run(id);
      }
      need(validCount(revision + 1), 'Budget revision overflow');
      this.db.prepare('UPDATE budget_roots SET revision=revision+1 WHERE id=?').run(rootSessionId);
      return this.snapshot(rootSessionId);
    });
  }

  assertDeadline(limits) { need(limits.deadlineAt === undefined || this.now() < limits.deadlineAt, 'Root budget deadline exceeded'); }

  reserveRequest({ sessionId, provider, model, purpose = 'conversation', outputUpper = 0, outputBoundKnown = false, inputUpper, inputBoundKnown = false, pricing }) {
    identifier(provider); identifier(model); identifier(purpose);
    need(validCount(outputUpper) && (inputUpper === undefined || validCount(inputUpper)), 'Invalid request reservation');
    const rates = validatePricing(pricing);
    return this.transaction(() => {
      const state = this.snapshot(sessionId), limits = state.limits;
      this.assertDeadline(limits);
      if (limits.maxOutputTokens !== undefined || limits.maxCostMicros !== undefined) {
        need(outputBoundKnown && outputUpper > 0, 'Hard budget requires a known enforced output bound');
        need(state.ambiguousRequests === 0 && !state.requestRecords.some(row => row.state === 'charged' && row.output_reserved === 0), 'Root budget has ambiguous usage; explicit reconciliation is required');
      }
      if (limits.maxCostMicros !== undefined) {
        need(inputBoundKnown && validCount(inputUpper) && rates, 'Hard cost budget requires known billing, input upper bound and integer pricing');
        need(!state.requestRecords.some(row => (['ambiguous', 'measured'].includes(row.state) && row.cost_micros === null)
          || (row.state === 'charged' && row.input_upper === null)), 'Root budget has unknown billing; explicit reconciliation is required');
      }
      const costReserved = rates && inputBoundKnown && inputUpper !== undefined
        ? priceUsage({ inputTokens: inputUpper, outputTokens: outputUpper, cacheReadTokens: 0, cacheWriteTokens: 0 }, { ...rates, input: Math.max(rates.input, rates.cacheRead, rates.cacheWrite) }) : 0;
      need(limits.maxRequests === undefined || state.requests < limits.maxRequests, 'Root request budget exceeded');
      need(limits.maxOutputTokens === undefined || sum([state.accountedOutputTokens, state.reserved.outputTokens, outputUpper]) <= limits.maxOutputTokens, 'Root output budget exceeded');
      need(limits.maxCostMicros === undefined || sum([state.accountedCostMicros, state.reserved.costMicros, costReserved]) <= limits.maxCostMicros, 'Root cost budget exceeded');
      const id = randomUUID();
      this.db.prepare('INSERT INTO budget_requests(id,root_id,session_id,owner_id,provider,model,purpose,state,output_reserved,input_upper,cost_reserved,pricing_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)')
        .run(id, state.rootSessionId, sessionId, this.owner, provider, model, purpose, 'reserved', outputUpper, inputBoundKnown ? inputUpper ?? null : null, costReserved, rates ? JSON.stringify(rates) : null);
      return id;
    });
  }

  markDispatched(id) {
    this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_requests WHERE id=?').get(identifier(id));
      need(row?.owner_id === this.owner && row.state === 'reserved', 'Request reservation cannot dispatch');
      this.assertDeadline(JSON.parse(this.db.prepare('SELECT limits_json FROM budget_roots WHERE id=?').get(row.root_id).limits_json));
      this.db.prepare("UPDATE budget_requests SET state='dispatched' WHERE id=?").run(id);
    });
  }

  cancelRequest(id) {
    this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_requests WHERE id=?').get(identifier(id));
      need(row?.owner_id === this.owner && ['reserved', 'cancelled'].includes(row.state), 'Only undispatched reservations can be cancelled');
      this.db.prepare("UPDATE budget_requests SET state='cancelled',cost_micros=0 WHERE id=?").run(id);
    });
  }

  settleRequest(id, { usage, complete = false } = {}) {
    return this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_requests WHERE id=?').get(identifier(id));
      need(row, 'Unknown budget request');
      const normalized = normalizedUsage(usage);
      const settlement = JSON.stringify({ usage: normalized ?? null, complete: complete === true });
      if (row.settlement_json !== null) { need(row.settlement_json === settlement, 'Budget settlement conflict'); return; }
      need(row.owner_id === this.owner && row.state === 'dispatched', 'Request reservation is not dispatched by this owner');
      const limits = JSON.parse(this.db.prepare('SELECT limits_json FROM budget_roots WHERE id=?').get(row.root_id).limits_json);
      const rates = row.pricing_json === null ? undefined : JSON.parse(row.pricing_json);
      const cost = complete ? priceUsage(normalized, rates) : null;
      const inputTotal = normalized && ['inputTokens', 'cacheReadTokens', 'cacheWriteTokens'].every(key => validCount(normalized[key]))
        ? sum([normalized.inputTokens, normalized.cacheReadTokens, normalized.cacheWriteTokens]) : null;
      const measured = complete && validCount(normalized?.outputTokens)
        && (row.output_reserved === 0 || normalized.outputTokens <= row.output_reserved)
        && (row.input_upper === null || (inputTotal !== null && inputTotal <= row.input_upper))
        && (limits.maxCostMicros === undefined || (cost !== null && cost <= row.cost_reserved));
      this.db.prepare('UPDATE budget_requests SET state=?,usage_json=?,cost_micros=?,settlement_json=? WHERE id=?')
        .run(measured ? 'measured' : 'ambiguous', normalized ? JSON.stringify(normalized) : null, measured ? cost : null, settlement, id);
    });
  }

  reserveChild({ parentId, childId, kind, provider }) {
    identifier(childId); identifier(provider); need(['local', 'external'].includes(kind), 'Invalid child execution kind');
    return this.transaction(() => {
      const state = this.snapshot(parentId), limits = state.limits;
      this.assertDeadline(limits);
      need(kind !== 'external' || (limits.maxOutputTokens === undefined && limits.maxCostMicros === undefined && limits.maxRequests === undefined), 'Hard model budgets cannot admit opaque external execution');
      need(limits.maxChildren === undefined || state.children < limits.maxChildren, 'Root total child budget exceeded');
      need(limits.maxConcurrentChildren === undefined || state.activeChildren < limits.maxConcurrentChildren, 'Root concurrent child budget exceeded');
      const known = this.db.prepare('SELECT * FROM budget_sessions WHERE id=?').get(childId);
      need(!known || (kind === 'local' && known.root_id === state.rootSessionId && known.parent_id === parentId), 'Budget child lineage conflict');
      if (kind === 'local' && !known) this.db.prepare('INSERT INTO budget_sessions VALUES(?,NULL,?,?)').run(childId, parentId, state.rootSessionId);
      const id = randomUUID();
      this.db.prepare('INSERT INTO budget_children VALUES(?,?,?,?,?,?,?,?)').run(id, state.rootSessionId, parentId, childId, this.owner, kind, provider, 'reserved');
      return id;
    });
  }

  publishChild(id, childId) {
    identifier(childId);
    this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_children WHERE id=?').get(identifier(id));
      need(row?.owner_id === this.owner && row.state === 'reserved', 'Child reservation cannot publish');
      need(row.kind === 'external' || row.child_id === childId, 'Local child identity changed');
      this.db.prepare("UPDATE budget_children SET state='published',child_id=? WHERE id=?").run(childId, id);
    });
  }

  settleChild(id, { quiescent }) {
    this.transaction(() => {
      const row = this.db.prepare('SELECT * FROM budget_children WHERE id=?').get(identifier(id));
      need(row, 'Unknown child reservation');
      if (row.state === 'settled') return;
      need(row.owner_id === this.owner, 'Child reservation belongs to another owner');
      this.db.prepare('UPDATE budget_children SET state=? WHERE id=?').run(quiescent === true ? 'settled' : 'ambiguous', id);
    });
  }

  close() {
    if (this.closed) return;
    this.transaction(() => this.orphanOwner(this.owner));
    this.closed = true;
    this.db.close();
  }
}
