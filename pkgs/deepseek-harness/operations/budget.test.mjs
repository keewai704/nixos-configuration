import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { BudgetLedger, BudgetError, priceUsage } from './budget.mjs';

function fixture(t, limits = {}, options = {}) {
  const root = mkdtempSync(join(tmpdir(), 'dsh-budget-'));
  const path = join(root, 'budget.sqlite');
  let ledger = new BudgetLedger(path, options);
  ledger.bindSession({ id: 'root', createdAt: 1 }, limits);
  t.after(() => { ledger.close(); assert.ok(root.startsWith(join(tmpdir(), 'dsh-budget-'))); rmSync(root, { recursive: true }); });
  return { root, path, get ledger() { return ledger; }, restart() { ledger.close(); ledger = new BudgetLedger(path, options); return ledger; } };
}

const route = { provider: 'audited-api', model: 'model', outputUpper: 20, outputBoundKnown: true };
const pricing = { input: 2_000_000, output: 4_000_000, cacheRead: 1_000_000, cacheWrite: 3_000_000 };
const usage = { inputTokens: 3, outputTokens: 7, cacheReadTokens: 1, cacheWriteTokens: 0 };

test('shares request and output reservations by persisted root lineage', t => {
  const f = fixture(t, { maxRequests: 2, maxOutputTokens: 30 });
  f.ledger.bindSession({ id: 'child', createdAt: 2, parentId: 'root' });
  const first = f.ledger.reserveRequest({ sessionId: 'child', ...route });
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /output budget/);
  f.ledger.markDispatched(first);
  f.ledger.settleRequest(first, { usage, complete: true });
  f.restart();
  assert.equal(f.ledger.rootFor('child'), 'root');
  const second = f.ledger.reserveRequest({ sessionId: 'root', ...route });
  f.ledger.markDispatched(second);
  f.ledger.settleRequest(second, { usage, complete: true });
  assert.equal(f.ledger.snapshot('child').usage.outputTokens, 14);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'child', ...route }), /request budget/);
});

test('SQLite transactions prevent separate ledger instances oversubscribing', t => {
  const f = fixture(t, { maxOutputTokens: 25 });
  const other = new BudgetLedger(f.path);
  t.after(() => other.close());
  f.ledger.reserveRequest({ sessionId: 'root', ...route });
  assert.throws(() => other.reserveRequest({ sessionId: 'root', ...route }), /output budget/);
  assert.equal(other.snapshot('root').reserved.outputTokens, 20);
});

test('hard limits reject unknown output and billing before admission', t => {
  const f = fixture(t, { maxOutputTokens: 100, maxCostMicros: 1000 });
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', provider: 'opaque', model: 'm', outputUpper: 20 }), /known enforced output/);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /known billing/);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route, pricing, inputUpper: 40 }), /known billing/);
  assert.equal(f.ledger.snapshot('root').requests, 0);
});

test('charges disjoint token usage and immutable integer prices once', t => {
  const f = fixture(t, { maxCostMicros: 300 });
  const id = f.ledger.reserveRequest({ sessionId: 'root', ...route, pricing, inputUpper: 40, inputBoundKnown: true });
  f.ledger.markDispatched(id);
  f.ledger.settleRequest(id, { usage, complete: true });
  f.ledger.settleRequest(id, { usage, complete: true });
  assert.equal(priceUsage(usage, pricing), 35);
  assert.equal(f.ledger.snapshot('root').usage.costMicros, 35);
  assert.throws(() => f.ledger.settleRequest(id, { usage: { ...usage, outputTokens: 8 }, complete: true }), /settlement conflict/);
});

test('unknown usage latches hard-cap admission and survives restart', t => {
  const f = fixture(t, { maxOutputTokens: 100 });
  const id = f.ledger.reserveRequest({ sessionId: 'root', ...route });
  f.ledger.markDispatched(id);
  f.ledger.settleRequest(id, { complete: false });
  f.restart();
  assert.equal(f.ledger.snapshot('root').ambiguousRequests, 1);
  assert.equal(f.ledger.snapshot('root').reserved.outputTokens, 20);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /ambiguous usage/);
});

test('closing an owner with outstanding requests preserves ambiguous reservation', t => {
  const f = fixture(t, { maxOutputTokens: 100 });
  f.ledger.reserveRequest({ sessionId: 'root', ...route });
  f.restart();
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /ambiguous usage/);
});

test('bounded children include opaque external children and retain uncertain slots', t => {
  const f = fixture(t, { maxChildren: 3, maxConcurrentChildren: 1 });
  const child = f.ledger.reserveChild({ parentId: 'root', childId: 'external-pending', kind: 'external', provider: 'opaque' });
  assert.throws(() => f.ledger.reserveChild({ parentId: 'root', childId: 'local', kind: 'local', provider: 'spawn' }), /concurrent child budget/);
  f.ledger.publishChild(child, 'external-id');
  f.ledger.settleChild(child, { quiescent: false });
  f.restart();
  assert.equal(f.ledger.snapshot('root').activeChildren, 1);
  assert.throws(() => f.ledger.reserveChild({ parentId: 'root', childId: 'local', kind: 'local', provider: 'spawn' }), /concurrent child budget/);
});

test('disposal release is idempotent but child totals are never refunded', t => {
  const f = fixture(t, { maxChildren: 1, maxConcurrentChildren: 1 });
  const id = f.ledger.reserveChild({ parentId: 'root', childId: 'one', kind: 'local', provider: 'spawn' });
  f.ledger.settleChild(id, { quiescent: true });
  f.ledger.settleChild(id, { quiescent: true });
  assert.equal(f.ledger.snapshot('root').activeChildren, 0);
  assert.throws(() => f.ledger.reserveChild({ parentId: 'root', childId: 'two', kind: 'local', provider: 'spawn' }), /total child budget/);
});

test('external execution is denied for hard token or cost limits', t => {
  const f = fixture(t, { maxOutputTokens: 200 });
  assert.throws(() => f.ledger.reserveChild({ parentId: 'root', childId: 'opaque', kind: 'external', provider: 'opaque' }), /opaque external/);
  assert.equal(f.ledger.snapshot('root').children, 0);
});

test('deadlines do not renew and changed session identities are rejected', t => {
  let now = 20;
  const f = fixture(t, { deadlineAt: 30 }, { now: () => now });
  assert.throws(() => f.ledger.bindSession({ id: 'root', createdAt: 999 }), /session identity/);
  assert.throws(() => f.ledger.bindSession({ id: 'orphan', createdAt: 2, parentId: 'missing' }), /lineage unavailable/);
  f.restart(); now = 30;
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /deadline/);
});

test('tracking mode reports unknown costs without pretending zero means known', t => {
  const f = fixture(t);
  const id = f.ledger.reserveRequest({ sessionId: 'root', provider: 'subscription', model: 'm' });
  f.ledger.markDispatched(id);
  f.ledger.settleRequest(id, { usage, complete: true });
  assert.equal(f.ledger.snapshot('root').usage.outputTokens, 7);
  assert.equal(f.ledger.snapshot('root').usage.costMicros, null);
  assert.equal(f.ledger.snapshot('root').unknownCostRequests, 1);
});

test('strict usage validation does not refund contradictory or over-bound counts', t => {
  const f = fixture(t, { maxOutputTokens: 100 });
  const id = f.ledger.reserveRequest({ sessionId: 'root', ...route });
  f.ledger.markDispatched(id);
  f.ledger.settleRequest(id, { usage: { ...usage, outputTokens: 21 }, complete: true });
  assert.equal(f.ledger.snapshot('root').ambiguousRequests, 1);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), BudgetError);
});

test('explicit reconciliation charges the full reservation without inventing measured usage', t => {
  const f = fixture(t, { maxOutputTokens: 30 });
  const id = f.ledger.reserveRequest({ sessionId: 'root', ...route });
  f.ledger.markDispatched(id);
  f.ledger.settleRequest(id, { complete: false });
  assert.throws(() => f.ledger.reconcile({ rootSessionId: 'root', revision: 1, requestIds: [id], confirmation: 'yes' }), /Explicit confirmation/);
  const state = f.ledger.reconcile({ rootSessionId: 'root', revision: 1, requestIds: [id], confirmation: `RECONCILE root 1 ${id} ` });
  assert.equal(state.usage.outputTokens, 0);
  assert.equal(state.accountedOutputTokens, 20);
  assert.equal(state.ambiguousRequests, 0);
  assert.throws(() => f.ledger.reserveRequest({ sessionId: 'root', ...route }), /output budget/);
});

test('budget configuration is revision bound and refuses outstanding requests', t => {
  const f = fixture(t, { maxRequests: 2 });
  const id = f.ledger.reserveRequest({ sessionId: 'root', ...route });
  assert.throws(() => f.ledger.configure({ rootSessionId: 'root', revision: 1, limits: { maxRequests: 4 }, confirmation: 'BUDGET root 1' }), /quiescent/);
  f.ledger.cancelRequest(id);
  assert.equal(f.ledger.configure({ rootSessionId: 'root', revision: 1, limits: { maxRequests: 4 }, confirmation: 'BUDGET root 1' }).revision, 2);
  assert.throws(() => f.ledger.configure({ rootSessionId: 'root', revision: 1, limits: {}, confirmation: 'BUDGET root 1' }), /revision/);
});

test('concurrent fully priced reservations remain admissible within the cap', t => {
  const f = fixture(t, { maxCostMicros: 1000 });
  const spec = { sessionId: 'root', ...route, pricing, inputUpper: 40, inputBoundKnown: true };
  f.ledger.reserveRequest(spec);
  f.ledger.reserveRequest(spec);
  assert.equal(f.ledger.snapshot('root').reserved.costMicros, 400);
});

test('refuses symlinked databases and unsupported existing schema', t => {
  const f = fixture(t);
  const alias = join(f.root, 'alias.sqlite');
  symlinkSync(f.path, alias);
  assert.throws(() => new BudgetLedger(alias), /Unsafe|symlink/);
  const invalid = join(f.root, 'invalid.sqlite');
  writeFileSync(invalid, 'not sqlite', { mode: 0o600 });
  assert.throws(() => new BudgetLedger(invalid));
});
