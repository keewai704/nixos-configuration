import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { makeChannelPlugin } from './privacy-channels.mjs';
import { gateSessionReporter } from './privacy-otel.mjs';

const require = createRequire(join(process.env.DSH_TEST_KERNEL ?? process.cwd(), 'package.json'));
const { Context } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis')).href);

function policy() {
  let value = false;
  let reconcile;
  return {
    enabled: () => value,
    attach(_id, _read, callback) { reconcile = callback; return () => {}; },
    async change(enabled) { value = enabled; await reconcile?.(); },
  };
}

test('real feedback backend mounts behind isolated consent and discards pending on disable', async () => {
  const { default: Upstream } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-session-telemetry-otel')).href);
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'dsh-privacy-feedback-'));
  const saved = process.env.DSH_HOME; process.env.DSH_HOME = root;
  writeFileSync(join(root, '.anonymous-user-id'), 'd9c74191-1293-4e4b-9fc4-03baf2276332', { mode: 0o600 });
  const ctx = new Context(); const p = policy(); const events = [];
  ctx.provide('privacyPolicy', p);
  ctx.provide('sessions', { get: () => undefined, list: () => [] });
  const otel = { createSessionLogReporter() {
    events.push('created');
    return { reportSessionLog() { throw Error('No feedback requested'); }, stopPending() { events.push('stop'); }, async shutdown() { events.push('shutdown'); } };
  } };
  const bridge = ctx.isolate('otel');
  try {
    await bridge.plugin({ apply(child) { child.provide('otel', gateSessionReporter(otel, p)); } });
    await bridge.plugin(makeChannelPlugin('session-telemetry-otel', Upstream, 'mode', 'FEEDBACK_ONLY', 'DISABLED'), { mode: 'DISABLED', exporter: { url: 'https://example.invalid/no-network' } });
    assert.equal(ctx.get('sessionTelemetry').sharing, 'disabled');
    assert.deepEqual(events, []);
    await p.change(true);
    assert.equal(ctx.get('sessionTelemetry').sharing, 'feedback-only');
    await p.change(false);
    assert.equal(ctx.get('sessionTelemetry').sharing, 'disabled');
    assert.deepEqual(events, ['created', 'stop', 'shutdown']);
  } finally {
    await ctx.fiber.dispose();
    if (saved === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME = saved;
    assert.equal(realpathSync(root), root); assert.match(root, /\/dsh-privacy-feedback-[^/]+$/); rmSync(root, { recursive: true });
  }
});

test('real analytics service refuses identity access while consent is disabled', async () => {
  const web = createRequire(join(process.env.DSH_TEST_WEB ?? process.env.DSH_TEST_KERNEL ?? process.cwd(), 'package.json'));
  const { default: Upstream } = await import(pathToFileURL(web.resolve('@deepseek-ai/dsh-client-product-analytics')).href);
  class Analytics extends Upstream {
    static inject = [...Upstream.inject, 'privacyPolicy'];
    enabled() { return this.ctx.privacyPolicy.enabled('product-analytics') && super.enabled(); }
  }
  const ctx = new Context(); const p = policy(); let identities = 0; let reports = 0;
  ctx.provide('privacyPolicy', p);
  ctx.provide('deepseekAccount', { async getDeviceIdentity() { identities++; return {}; } });
  ctx.provide('productTelemetry', { emit() { reports++; } });
  try {
    await ctx.plugin(makeChannelPlugin('product-analytics', Analytics, 'enabled', true, false), { appVersion: 'test', enabled: false });
    assert.equal(ctx.get('productAnalytics').enabled(), false);
    await ctx.get('productAnalytics').report({ eventName: 'fixture', timestamp: 0, attributes: {} });
    assert.equal(identities, 0); assert.equal(reports, 0);
  } finally { await ctx.fiber.dispose(); }
});
