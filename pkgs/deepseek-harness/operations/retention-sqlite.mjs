import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const ensure = (condition, message) => { if (!condition) throw new Error(message); };
const schemas = {
  'operations/privacy.sqlite': {
    tables: { privacy_choices: 'channel:TEXT enabled:INTEGER revision:INTEGER updated_at:INTEGER' },
    indexes: [],
  },
  'operations/budget.sqlite': {
    tables: {
      budget_meta: 'key:TEXT value:TEXT',
      budget_owners: 'id:TEXT pid:INTEGER start:TEXT closed:INTEGER',
      budget_roots: 'id:TEXT limits_json:TEXT revision:INTEGER',
      budget_sessions: 'id:TEXT created_at:INTEGER parent_id:TEXT root_id:TEXT',
      budget_requests: 'id:TEXT root_id:TEXT session_id:TEXT owner_id:TEXT provider:TEXT model:TEXT purpose:TEXT state:TEXT output_reserved:INTEGER input_upper:INTEGER cost_reserved:INTEGER pricing_json:TEXT usage_json:TEXT cost_micros:INTEGER settlement_json:TEXT',
      budget_children: 'id:TEXT root_id:TEXT parent_id:TEXT child_id:TEXT owner_id:TEXT kind:TEXT provider:TEXT state:TEXT',
    },
    indexes: ['budget_requests_root', 'budget_children_root'],
  },
  'operations/checkpoints.sqlite': {
    tables: {
      checkpoint_runs: 'id:TEXT root_id:TEXT root_identity:TEXT status:TEXT revision:INTEGER created_at:INTEGER updated_at:INTEGER deadline_at:INTEGER graph_json:TEXT backend:TEXT cwd:TEXT max_attempts:INTEGER attempts_started:INTEGER owner_token:TEXT',
      checkpoint_nodes: 'run_id:TEXT id:TEXT status:TEXT attempt:INTEGER',
      checkpoint_attempts: 'run_id:TEXT node_id:TEXT attempt:INTEGER status:TEXT child_id:TEXT result_json:TEXT error:TEXT started_at:INTEGER finished_at:INTEGER',
      checkpoint_actions: 'id:TEXT run_id:TEXT root_id:TEXT action:TEXT prior_revision:INTEGER at:INTEGER actor:TEXT',
    },
    indexes: ['checkpoint_owner'],
  },
};

export function scanOperationDatabase(tree, relative, refs, { collect, parseJson, hash, raw }) {
  const schema = schemas[relative];
  if (!schema) return null;
  const observed = tree.read(relative);
  raw(observed.data);
  ensure(observed.data.subarray(0, 16).toString('latin1') === 'SQLite format 3\0', `Malformed operations database: ${relative}`);
  const names = tree.directory('operations');
  for (const suffix of ['-wal', '-shm', '-journal']) ensure(!names.includes(`${relative.slice('operations/'.length)}${suffix}`), `SQLite sidecar requires checkpoint/recovery before retention: ${relative}${suffix}`);
  const { DatabaseSync } = createRequire(import.meta.url)('node:sqlite');
  const url = pathToFileURL(tree.absolute(relative));
  url.searchParams.set('mode', 'ro');
  url.searchParams.set('immutable', '1');
  const db = new DatabaseSync(url.href, { readOnly: true, enableDoubleQuotedStringLiterals: false, allowExtension: false });
  let rows = 0;
  try {
    db.exec('PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; PRAGMA busy_timeout=0;');
    ensure(db.prepare('PRAGMA user_version').get().user_version === 1, `Unknown operations database version: ${relative}`);
    ensure(db.prepare('PRAGMA quick_check(1)').get().quick_check === 'ok', `Corrupt operations database: ${relative}`);
    const entries = db.prepare('SELECT type,name,tbl_name,sql FROM sqlite_schema LIMIT 101').all();
    ensure(entries.length <= 100, `Operations database schema bound exceeded: ${relative}`);
    for (const entry of entries) {
      ensure(entry.type === 'table' ? Object.hasOwn(schema.tables, entry.name) && !/VIRTUAL/i.test(entry.sql) : entry.type === 'index' && Object.hasOwn(schema.tables, entry.tbl_name) && (entry.sql === null || schema.indexes.includes(entry.name)), `Unknown operations database schema: ${relative}`);
    }
    ensure(entries.filter(entry => entry.type === 'table').length === Object.keys(schema.tables).length, `Incomplete operations database schema: ${relative}`);
    for (const [table, columns] of Object.entries(schema.tables)) {
      const actual = db.prepare(`PRAGMA table_xinfo('${table}')`).all();
      ensure(actual.every(column => column.hidden === 0) && actual.map(column => `${column.name}:${column.type}`).join(' ') === columns, `Unknown operations database columns: ${relative}/${table}`);
      const statement = db.prepare(`SELECT * FROM "${table}" LIMIT 100001`);
      statement.setReadBigInts(true);
      for (const row of statement.iterate()) {
        ensure(++rows <= 100_000, `Operations database row bound exceeded: ${relative}`);
        for (const [key, value] of Object.entries(row)) {
          ensure(value === null || typeof value === 'string' || typeof value === 'bigint', `Unknown operations database value encoding: ${relative}`);
          if (typeof value !== 'string') continue;
          const data = Buffer.from(value);
          ensure(data.length <= 16 * 1024 * 1024, `Operations database cell bound exceeded: ${relative}`);
          tree.total += data.length;
          ensure(tree.total <= 1024 * 1024 * 1024, 'Total scan byte limit exceeded');
          raw(data);
          collect(value, refs, relative);
          if (key.endsWith('_json')) collect(parseJson(data, `${relative}/${table}/${key}`), refs, relative);
        }
      }
    }
  } finally { db.close(); }
  tree.assertUnchanged(relative, observed.entry);
  ensure(JSON.stringify(tree.directory('operations')) === JSON.stringify(names), `SQLite created or changed sidecars: ${relative}`);
  return { path: relative, bytes: observed.data.length, sha256: hash(observed.data), schemaVersion: 1, rows };
}
