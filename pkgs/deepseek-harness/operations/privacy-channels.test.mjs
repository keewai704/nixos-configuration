import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { makeChannelPlugin, makeExtensionChannelPlugin } from './privacy-channels.mjs';

const require = createRequire(join(process.env.DSH_TEST_KERNEL ?? process.cwd(), 'package.json'));
const { Context } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis')).href);

function policy() {
  const settings = new Map();
  const attachments = new Map();
  return {
    enabled: id => settings.get(id) === true,
    attach(id, read, reconcile) { attachments.set(id, { read, reconcile }); return () => attachments.delete(id); },
    async change(id, enabled) { settings.set(id, enabled); await attachments.get(id)?.reconcile?.(); },
    status: id => attachments.get(id)?.read(),
    settings,
  };
}

test('isolated request extension bridge blocks both before and after async preparation', async () => {
  const ctx = new Context(); const p = policy(); const providers = new Map(); let release; let calls = 0;
  ctx.provide('privacyPolicy', p);
  ctx.provide('deepseekLlmApiExtensions', { register: (id, provider) => { providers.set(id, provider); return () => providers.delete(id); } });
  const upstream = {
    inject: ['deepseekLlmApiExtensions'],
    apply(child) { child.effect(() => child.deepseekLlmApiExtensions.register('test', { async prepare() { calls++; await new Promise(resolve => { release = resolve; }); return { value: 'private' }; } })); },
  };
  try {
    await ctx.plugin(makeExtensionChannelPlugin('session-log-deepseek', upstream));
    assert.equal(await providers.get('test').prepare({}), undefined);
    assert.equal(calls, 0);
    await p.change('session-log-deepseek', true);
    const pending = providers.get('test').prepare({});
    await p.change('session-log-deepseek', false);
    release();
    assert.equal(await pending, undefined);
    assert.equal(calls, 1);
    assert.equal(p.status('session-log-deepseek'), 'disabled');
  } finally { await ctx.fiber.dispose(); }
  assert.equal(providers.size, 0);
});

test('child provider teardown completes before a new consent mode activates', async () => {
  const ctx = new Context(); const p = policy(); const active = [];
  ctx.provide('privacyPolicy', p);
  const upstream = {
    apply(child, config) {
      assert.equal(active.length, 0);
      active.push(config.mode);
      child.effect(() => async () => { await Promise.resolve(); active.pop(); });
    },
  };
  try {
    await ctx.plugin(makeChannelPlugin('session-telemetry-otel', upstream, 'mode', 'on', 'off'));
    assert.deepEqual(active, ['off']);
    await p.change('session-telemetry-otel', true);
    assert.deepEqual(active, ['on']);
    await p.change('session-telemetry-otel', false);
    assert.deepEqual(active, ['off']);
  } finally { await ctx.fiber.dispose(); }
  assert.deepEqual(active, []);
});

test('real pinned session-log and inventory extensions mount without requests', async () => {
  for (const [id, name] of [['session-log-deepseek', '@deepseek-ai/dsh-session-log-deepseek'], ['plugin-package-inventory-deepseek', '@deepseek-ai/dsh-plugin-package-inventory-deepseek']]) {
    const upstream = await import(pathToFileURL(require.resolve(name)).href);
    const ctx = new Context(); const p = policy(); const providers = new Map();
    ctx.provide('privacyPolicy', p);
    ctx.provide('sessions', { get: () => undefined });
    ctx.provide('agents', { get: () => undefined });
    ctx.provide('loader', { entries: () => [] });
    ctx.provide('deepseekLlmApiExtensions', { register: (field, provider) => { providers.set(field, provider); return () => providers.delete(field); } });
    try {
      await ctx.plugin(makeExtensionChannelPlugin(id, upstream), { enabled: false });
      assert.equal(providers.size, 1);
      for (const provider of providers.values()) assert.equal(await provider.prepare({}), undefined);
      assert.equal(p.status(id), 'disabled');
    } finally { await ctx.fiber.dispose(); }
  }
});
