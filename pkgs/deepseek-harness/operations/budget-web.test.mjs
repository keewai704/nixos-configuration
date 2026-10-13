import test from 'node:test';
import assert from 'node:assert/strict';
import { registerBudgetRoutes } from './budget-web.mjs';

function fixture() {
  const routes = new Map(); const calls = [];
  let agent = { id: 'root', status: 'idle', session: { header: { id: 'root', createdAt: 1 } } };
  const policy = {
    bindSession: async () => {}, snapshot: id => ({ rootSessionId: id, revision: 1, limits: {} }), capabilities: () => ({ persisted: true }),
    configure: input => { calls.push(input); return { applied: true }; }, reconcile: input => { calls.push(input); return { reconciled: true }; },
  };
  const ctx = { budgetPolicy: policy, agents: { list: () => [agent], get: id => id === agent.id ? agent : undefined }, effect: execute => execute(), connection: { fetch: { register: route => { routes.set(route.path, route); return () => {}; } } } };
  registerBudgetRoutes(ctx);
  return { routes, calls, policy, busy: () => { agent.status = 'running'; }, replace: () => { agent = { ...agent }; } };
}

function request(body, extra = {}) {
  return new Request('http://dsh.internal/api/operations/budgets/configure', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dsh-operations': '1', host: 'dsh.invalid', origin: 'https://dsh.invalid', ...extra }, body: JSON.stringify(body) });
}

test('budget controls use authenticated carrier synthetic URL and forward explicit revision confirmation', async () => {
  const { routes, calls } = fixture();
  const input = { rootSessionId: 'root', revision: 1, limits: { maxRequests: 20 }, confirmation: 'BUDGET root 1' };
  const result = await routes.get('/api/operations/budgets/configure').fetch(request(input));
  assert.equal(result.status, 200); assert.deepEqual(calls, [input]);
  assert.equal((await routes.get('/api/operations/budgets').fetch(new Request('http://dsh.internal/api/operations/budgets'))).status, 200);
});

test('budget operator routes refuse foreign origins and undeclared roots without mutation', async () => {
  const { routes, calls } = fixture(); const handler = routes.get('/api/operations/budgets/configure').fetch;
  for (const origin of ['null', 'https://elsewhere.invalid', 'https://dsh.invalid/with-path', 'https://user@dsh.invalid']) assert.equal((await handler(request({ rootSessionId: 'root' }, { origin }))).status, 403);
  assert.equal((await handler(request({ rootSessionId: 'missing' }))).status, 409);
  assert.equal((await handler(request({ rootSessionId: 'root' }, { 'x-dsh-operations': '0' }))).status, 403);
  assert.equal(calls.length, 0);
});

test('budget changes refuse a busy root even after model accounting has settled', async () => {
  const f = fixture(); f.busy();
  const response = await f.routes.get('/api/operations/budgets/configure').fetch(request({ rootSessionId: 'root', revision: 1, limits: {}, confirmation: 'BUDGET root 1' }));
  assert.equal(response.status, 409); assert.equal(f.calls.length, 0);
});

test('asynchronous budget binding cannot mutate a replaced root', async () => {
  const f = fixture();
  f.policy.bindSession = async () => { f.replace(); };
  const response = await f.routes.get('/api/operations/budgets/configure').fetch(request({ rootSessionId: 'root' }));
  assert.equal(response.status, 409); assert.equal(f.calls.length, 0);
});
