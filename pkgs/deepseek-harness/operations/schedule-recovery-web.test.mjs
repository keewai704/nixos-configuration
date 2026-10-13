import test from 'node:test';
import assert from 'node:assert/strict';
import { registerScheduleRecoveryRoutes } from './schedule-recovery-web.mjs';

function setup() {
  const routes = new Map(); const calls = [];
  const service = { list: async () => ({ version: 1, obligations: [{ id: 'same-id', revision: 'r1', retryable: true }] }), retry: async input => { calls.push(input); return { id: input.id, revision: 'r2', retryable: false }; } };
  registerScheduleRecoveryRoutes({ scheduleRecovery: service, effect: callback => callback(), connection: { fetch: { register: route => { routes.set(route.path, route.fetch); return () => {}; } } } });
  return { routes, calls, service };
}
function request(input, headers = {}) {
  return new Request('http://dsh.internal/api/operations/deliveries/retry', { method: 'POST', body: JSON.stringify(input), headers: { host: 'dsh.invalid', origin: 'https://dsh.invalid', 'content-type': 'application/json', 'x-dsh-operations': '1', ...headers } });
}

test('delivery retry forwards exact confirmation to owned service and returns only redacted receipt', async () => {
  const f = setup(); const input = { id: 'same-id', expectedRevision: 'r1', confirmation: 'RETRY DELIVERY same-id r1' };
  const result = await f.routes.get('/api/operations/deliveries/retry')(request(input));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { obligation: { id: 'same-id', revision: 'r2', retryable: false } });
  assert.deepEqual(f.calls, [input]);
  assert.equal((await f.routes.get('/api/operations/deliveries')(new Request('http://dsh.internal/api/operations/deliveries'))).status, 200);
});

test('delivery recovery rejects cross-origin, missing-header and unknown-field mutations', async () => {
  const f = setup(); const handler = f.routes.get('/api/operations/deliveries/retry');
  for (const origin of ['null', 'https://other.invalid', 'https://dsh.invalid/path', 'https://user@dsh.invalid']) assert.equal((await handler(request({}, { origin }))).status, 403);
  assert.equal((await handler(request({}, { 'x-dsh-operations': '0' }))).status, 403);
  assert.equal((await handler(request({ granted: true }))).status, 400);
  assert.equal(f.calls.length, 0);
});

test('stale or unapproved service decisions remain failures without exposing internal data', async () => {
  const f = setup(); f.service.retry = async () => { throw Object.assign(new Error('private prompt'), { code: 'stale_revision' }); };
  const response = await f.routes.get('/api/operations/deliveries/retry')(request({}));
  assert.equal(response.status, 409);
  const body = await response.text(); assert.match(body, /stale_revision/); assert.doesNotMatch(body, /private prompt/);
});
