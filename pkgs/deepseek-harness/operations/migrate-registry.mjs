export const MAX_FILE = 32 * 1024 * 1024;
export const MAX_TOTAL = 256 * 1024 * 1024;
export const MAX_RECORDS = 2000;
export const ensure = (condition, message) => { if (!condition) throw new Error(message); };
export const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export const encodeJson = value => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);

export function parseJson(bytes) {
  ensure(bytes.length <= MAX_FILE, 'JSON byte bound exceeded');
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  let cursor = 0;
  let nodes = 0;
  const space = () => { while (/[ \t\r\n]/.test(text[cursor] ?? 'x')) cursor++; };
  const string = () => {
    const start = cursor++;
    while (cursor < text.length) {
      const character = text[cursor++];
      if (character === '\\') cursor++;
      else if (character === '"') return JSON.parse(text.slice(start, cursor));
    }
    throw new Error('Unterminated JSON string');
  };
  const value = depth => {
    ensure(depth <= 128 && ++nodes <= 1_000_000, 'JSON structural bound exceeded');
    space();
    const token = text[cursor];
    if (token === '"') { string(); return; }
    if (token === '{' || token === '[') {
      cursor++;
      const closing = token === '{' ? '}' : ']';
      const keys = new Set();
      space();
      if (text[cursor] === closing) { cursor++; return; }
      for (;;) {
        if (token === '{') {
          ensure(text[cursor] === '"', 'Invalid JSON object key');
          const key = string();
          ensure(!keys.has(key), `Duplicate JSON key: ${key}`);
          keys.add(key);
          space();
          ensure(text[cursor++] === ':', 'Invalid JSON key separator');
        }
        value(depth + 1);
        space();
        const separator = text[cursor++];
        if (separator === closing) return;
        ensure(separator === ',', 'Invalid JSON separator');
        space();
      }
    }
    const match = /^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(text.slice(cursor));
    ensure(match, 'Invalid JSON value');
    if (!['true', 'false', 'null'].includes(match[0])) {
      const number = Number(match[0]);
      ensure(Number.isFinite(number) && Math.abs(number) <= Number.MAX_SAFE_INTEGER && !Object.is(number, -0), 'Lossy JSON number');
    }
    cursor += match[0].length;
  };
  value(0);
  space();
  ensure(cursor === text.length, 'Trailing JSON data');
  return JSON.parse(text);
}

function keys(value, required, optional = []) {
  ensure(object(value), 'Expected schema object');
  ensure(required.every(key => Object.hasOwn(value, key)), `Missing schema field: ${required.join(', ')}`);
  ensure(Object.keys(value).every(key => required.includes(key) || optional.includes(key)), 'Unsupported schema field');
}

function checkpoint(record, legacy) {
  keys(record, ['identity', 'rows']);
  keys(record.identity, ['createdAt'], legacy ? ['cwd'] : ['cwd', 'formatVersion', 'isSeeded', 'inheritedEventCount']);
  for (const key of ['createdAt', 'formatVersion', 'inheritedEventCount']) {
    if (Object.hasOwn(record.identity, key)) ensure(Number.isSafeInteger(record.identity[key]) && record.identity[key] >= 0, `Invalid checkpoint ${key}`);
  }
  if (Object.hasOwn(record.identity, 'cwd')) ensure(typeof record.identity.cwd === 'string', 'Invalid checkpoint cwd');
  if (Object.hasOwn(record.identity, 'isSeeded')) ensure(typeof record.identity.isSeeded === 'boolean', 'Invalid checkpoint lineage');
  ensure(object(record.rows) && Object.keys(record.rows).length <= 10_000, 'Invalid checkpoint rows');
  for (const row of Object.values(record.rows)) {
    keys(row, ['ver', 'seq', 'val']);
    ensure(Number.isSafeInteger(row.ver) && row.ver >= 0, 'Invalid checkpoint row version');
    ensure(Number.isSafeInteger(row.seq) && row.seq >= -1, 'Invalid checkpoint row sequence');
  }
}

function validateSource(document) {
  keys(document, ['unit', 'global', 'tables']);
  keys(document.unit, ['name', 'version']);
  ensure(document.unit.name === 'session_projcache' && document.unit.version === 3, 'Unsupported source unit/version; expected session_projcache whole-unit v3');
  ensure(document.global === null, 'Unsupported non-null projection cache global');
  keys(document.tables, ['sessions']);
  ensure(object(document.tables.sessions), 'Invalid sessions table');
  const ids = Object.keys(document.tables.sessions);
  ensure(ids.length > 0 && ids.length <= MAX_RECORDS, 'Migration needs 1–2000 records');
  for (const id of ids) {
    ensure(/^[A-Za-z0-9_-]{1,180}$/.test(id), 'Unsafe or oversized session record key');
    checkpoint(document.tables.sessions[id], true);
  }
}

function validateOutput(document) {
  assertLossless(document);
  keys(document, ['version', 'record']);
  ensure(document.version === 7, 'Expected projection cache per-record v7');
  checkpoint(document.record, false);
}

function assertLossless(value, depth = 0, seen = new Set()) {
  ensure(depth <= 128, 'JSON structural bound exceeded');
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
  if (typeof value === 'number') {
    ensure(Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER && !Object.is(value, -0), 'Lossy JSON number');
    return;
  }
  ensure(object(value) || Array.isArray(value), 'Non-JSON checkpoint value');
  ensure(!seen.has(value), 'Cyclic checkpoint value');
  ensure(Array.isArray(value) || [null, Object.prototype].includes(Object.getPrototypeOf(value)), 'Non-JSON checkpoint object');
  seen.add(value);
  if (Array.isArray(value)) ensure(Object.keys(value).length === value.length, 'Sparse or extended checkpoint array');
  for (const entry of Object.values(value)) assertLossless(entry, depth + 1, seen);
  seen.delete(value);
}

const edge = Object.freeze({
  id: 'session-projcache-v3-to-v7',
  revision: 1,
  source: 'storages/session_projcache.json',
  directories: Object.freeze(['storages/session_projcache', 'storages/session_projcache/sessions']),
  inputSchema: 'dsh-0.2.1-alpha.2/session_projcache/single-v3-lineageless',
  outputSchema: 'dsh-0.2.1-alpha.2/session_projcache/per-record-v7',
  semantics: 'Split the pinned v3 whole-unit cache into v7 record documents. Preserve all checkpoint rows and lifecycle fields; do not invent Session format generation or lineage. The legacy source stays unchanged. Unbound checkpoints remain listing hints, never current fold shortcuts.',
  validateOutput,
  transform(document) {
    assertLossless(document);
    validateSource(document);
    let total = 0;
    return Object.keys(document.tables.sessions).sort().map(id => {
      const output = { version: 7, record: document.tables.sessions[id] };
      validateOutput(output);
      const data = encodeJson(output);
      ensure(data.length <= MAX_FILE, 'Transformed record exceeds byte bound');
      total += data.length;
      ensure(total <= MAX_TOTAL / 2, 'Transformed aggregate byte bound exceeded');
      return { path: `storages/session_projcache/sessions/${id}.json`, data };
    });
  },
});

export function migration(id) {
  ensure(id === edge.id, `Unsupported migration: ${id}; no arbitrary domain, schema, or transformation code is accepted`);
  return edge;
}
