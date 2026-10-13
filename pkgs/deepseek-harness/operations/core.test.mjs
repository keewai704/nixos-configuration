import assert from 'node:assert/strict';
import test from 'node:test';
import { privacySnapshot, changePrivacy, jsonRoute, retentionPreview, persistencePolicy } from './core.mjs';

function fixture() {
  const entries = [
    { id: 'root/session-log-deepseek', options: { id: 'session-log-deepseek', config: {} }, disabled: false, fiber: { uid: 1, state: 2, config: { enabled: { get: () => true } } } },
    { id: 'root/session-telemetry-otel', options: { id: 'session-telemetry-otel', config: { mode: 'DISABLED' } }, disabled: false, fiber: { uid: 2, state: 2, config: { mode: 'DISABLED' } } },
  ];
  const ctx = {
    loader: { entries: () => entries },
    configEditor: {
      entries: () => entries,
      configuration: () => entries.map(entry => ({ entry, inherited: {}, override: {} })),
      async edit(entry, change) { entry.options.config = change(entry.options.config, {}); },
    },
  };
  return { entries, ctx };
}

test('distinguishes explicit deployment persistence without guessing from Nix seed markers', async () => {
  const { ctx, entries } = fixture();
  assert.equal(persistencePolicy(ctx), 'unknown');
  const policy = { options: { id: 'operations' }, fiber: { config: { persistence: 'profile' } } };
  entries.push(policy);
  assert.equal(persistencePolicy(ctx), 'profile');
  policy.fiber.config.persistence = 'launch-reset';
  assert.equal(persistencePolicy(ctx), 'launch-reset');
  const row = privacySnapshot(ctx)[1];
  const outcome = await changePrivacy(ctx, { id: row.id, enabled: false, revision: row.revision, confirmation: `DISABLE ${row.id}` });
  assert.equal(outcome.persistence, 'launch-reset');
  policy.fiber.config.persistence = 'invalid';
  assert.equal(persistencePolicy(ctx), 'unknown');
});

test('reports four distinct channels and resolved volatile state', () => {
  const { ctx } = fixture();
  const rows = privacySnapshot(ctx);
  assert.equal(rows.length, 4);
  assert.equal(rows[0].effective, 'disabled');
  assert.equal(rows[1].effective, 'enabled');
  assert.equal(rows[2].effective, 'not-mounted');
  assert.equal(rows[3].editable, false);
  assert.equal(JSON.stringify(rows).includes('exporter'), false);
});

test('checks confirmation, allowlist and optimistic revision inside edit', async () => {
  const { ctx, entries } = fixture();
  const row = privacySnapshot(ctx)[1];
  const input = { id: row.id, enabled: false, revision: row.revision, confirmation: `DISABLE ${row.id}` };
  await assert.rejects(changePrivacy(ctx, { ...input, id: 'llm-claude-code' }), /Unknown/);
  await assert.rejects(changePrivacy(ctx, { ...input, confirmation: '' }), /confirmation/);
  await changePrivacy(ctx, input);
  assert.equal(entries[0].options.config.enabled, false);
  await assert.rejects(changePrivacy(ctx, input), /changed/);
});

test('preserves transport limits and credentials rather than restating them', async () => {
  const { ctx, entries } = fixture();
  entries[1].options.config = { mode: 'DISABLED', exporter: { url: 'https://private.invalid', headers: { token: 'secret' } }, maxRequestBytes: 8000 };
  const row = privacySnapshot(ctx)[0];
  assert.equal(JSON.stringify(row).includes('secret'), false);
  await changePrivacy(ctx, { id: row.id, enabled: true, revision: row.revision, confirmation: `ENABLE ${row.id}` });
  assert.equal(entries[1].options.config.mode, 'FEEDBACK_ONLY');
  assert.equal(entries[1].options.config.maxRequestBytes, 8000);
  assert.equal(entries[1].options.config.exporter.headers.token, 'secret');
});

test('inactive and overridden entries cannot look successfully enabled', async () => {
  const { ctx, entries } = fixture();
  entries[0].disabled = true;
  assert.equal(privacySnapshot(ctx)[1].editable, false);
  await assert.rejects(changePrivacy(ctx, { id: 'session-log-deepseek', enabled: true }), /active/);
});

test('mutations require JSON, same-origin browser header and small objects', async () => {
  const route = jsonRoute('POST', async data => data);
  assert.equal((await route(new Request('https://dsh.invalid/api/operations/privacy', { method: 'POST', body: '{}' }))).status, 415);
  assert.equal((await route(new Request('https://dsh.invalid/api/operations/privacy', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }))).status, 403);
  const request = body => new Request('https://dsh.invalid/api/operations/privacy', { method: 'POST', headers: { 'content-type': 'application/json', 'x-dsh-operations': '1' }, body });
  assert.equal((await route(request('['))).status, 400);
  assert.equal((await route(request('[]'))).status, 400);
  assert.equal((await route(request(JSON.stringify({ x: 'a'.repeat(33000) })))).status, 413);
  const response = await route(request('{"ok":true}'));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('retention preview is read-only and does not expose session contents', () => {
  const now = Date.now();
  const snapshot = [{ header: { id: 'old', createdAt: now - 366 * 86400000, cwd: '/private', title: 'private' }, sizeBytes: 123 }];
  const result = retentionPreview(snapshot, 365, now);
  assert.equal(result.candidates[0].id, 'old');
  assert.equal(result.candidateBytes, 123);
  assert.equal(result.deletionAvailable, false);
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.throws(() => retentionPreview(snapshot, 0), /days/);
});
