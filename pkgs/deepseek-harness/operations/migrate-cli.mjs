import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ensure } from './migrate-registry.mjs';
import { execute } from './migrate.mjs';

export function run(argv, env = process.env) {
  const args = [...argv];
  const action = args.shift();
  ensure(['plan', 'apply', 'recover', 'rollback'].includes(action), 'Usage: dsh-storage-migrate <plan|apply|recover|rollback> --home ABSOLUTE_DSH_HOME --migration session-projcache-v3-to-v7 (plan/apply); apply also needs --plan-hash HASH --confirm MIGRATE:HASH; recover/rollback need --transaction HASH --confirm RECOVER:HASH or ROLLBACK:HASH');
  const values = { action };
  const names = { '--home': 'home', '--migration': 'migration', '--plan-hash': 'planHash', '--confirm': 'confirm', '--transaction': 'transaction' };
  while (args.length) {
    const name = args.shift();
    ensure(Object.hasOwn(names, name), `Unknown option: ${name}`);
    const key = names[name];
    ensure(!Object.hasOwn(values, key), `Repeated option: ${name}`);
    const value = args.shift();
    ensure(typeof value === 'string' && value.length > 0 && !value.startsWith('--') && !value.includes('\0'), `Missing value for ${name}`);
    values[key] = value;
  }
  const allowed = ['home', ...(action === 'plan' ? ['migration'] : action === 'apply' ? ['migration', 'planHash', 'confirm'] : ['transaction', 'confirm'])];
  ensure(Object.keys(values).every(key => key === 'action' || allowed.includes(key)), `Invalid option for ${action}`);
  ensure(allowed.every(key => Object.hasOwn(values, key)), `Missing required ${action} options: ${allowed.join(', ')}`);
  return execute(values, env);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(run(process.argv.slice(2)), null, 2)); }
  catch (error) { console.error(`Migration refused: ${error.message}`); process.exitCode = 1; }
}
