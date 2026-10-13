import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { mkdtemp, readFile, readdir, realpath } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import vm from 'node:vm';
import {
  buildPlanClientPackage, originalPlanPackage, planTooltips,
  replacementPlanPackage, transformPlanClient,
} from './plan-client-build.mjs';

const input = process.env.DSH_PLAN_CLIENT_SOURCE;
assert.ok(input, 'Set DSH_PLAN_CLIENT_SOURCE to the pinned built ui-plan package directory');
const originalManifest = JSON.parse(await readFile(join(input, 'package.json'), 'utf8'));
const originalClient = await readFile(join(input, 'lib/client.js'), 'utf8');
const transformed = transformPlanClient(originalManifest, originalClient);

function uncorrectedClient() {
  let source = originalClient;
  for (const { original, corrected } of Object.values(planTooltips)) {
    source = source.replace(`"chip.on.title": ${JSON.stringify(corrected)}`, `"chip.on.title": ${JSON.stringify(original)}`);
  }
  return source;
}

test('package rename preserves dependencies and corrects only intended client identities and copy', () => {
  assert.deepEqual(transformed.manifest, { ...originalManifest, name: replacementPlanPackage });
  assert.equal(transformed.client, transformPlanClient(originalManifest, uncorrectedClient()).client);
  assert.match(transformed.client, /const previewId = "@deepseek-ai\/dsh-client-ui-plan";/);
  assert.equal(transformed.client.split(`tag.dataset.plugin = "${replacementPlanPackage}";`).length - 1, 2);
  assert.equal(transformed.client.includes(`tag.dataset.plugin = "${originalPlanPackage}";`), false);
  for (const { corrected } of Object.values(planTooltips)) {
    assert.equal(transformed.client.split(`"chip.on.title": ${JSON.stringify(corrected)}`).length - 1, 1);
  }
  const requests = source => [...source.matchAll(/\brequire\(("[^"]+")\)/g)].map(match => match[1]);
  assert.deepEqual(requests(transformed.client), requests(originalClient));
});

test('unknown package versions, duplicate registrations, changed tooltips and split bundles fail closed', () => {
  assert.throws(() => transformPlanClient({ ...originalManifest, version: 'next' }, originalClient), /pinned/);
  assert.throws(() => transformPlanClient(originalManifest, originalClient + originalClient), /occurrences/);
  const changed = uncorrectedClient().replace(planTooltips.en.original, 'Different upstream tooltip');
  assert.throws(() => transformPlanClient(originalManifest, changed), /tooltip/);
  assert.throws(() => transformPlanClient(originalManifest, `${originalClient}\nrequire.async('./client.extra.js');`), /split/);
});

test('builder copies package-local runtime assets without mutating upstream or replacing an existing output', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'dsh-plan-client-test-'));
  const output = await buildPlanClientPackage(input, join(parent, 'package'));
  assert.equal(output, join(await realpath(parent), 'package'));
  assert.deepEqual(JSON.parse(await readFile(join(output, 'package.json'), 'utf8')), transformed.manifest);
  assert.equal(await readFile(join(output, 'lib/client.js'), 'utf8'), transformed.client);
  async function compare(directory = 'lib') {
    for (const entry of await readdir(join(input, directory), { withFileTypes: true })) {
      const relative = join(directory, entry.name);
      if (entry.isDirectory()) await compare(relative);
      else if (relative !== 'lib/client.js') {
        assert.deepEqual(await readFile(join(output, relative)), await readFile(join(input, relative)), relative);
      }
    }
  }
  await compare();
  const host = await import(pathToFileURL(join(output, 'lib/index.js')));
  assert.equal(typeof host.apply, 'function');
  assert.equal(host.apply(), undefined);
  await assert.rejects(buildPlanClientPackage(input, output), { code: 'EEXIST' });
  await assert.rejects(buildPlanClientPackage(input, join(input, 'replacement')), /outside/);
  assert.equal(await readFile(join(input, 'lib/client.js'), 'utf8'), originalClient);
});

const runtime = process.env.DSH_PLAN_UPSTREAM;
const dependencies = process.env.DSH_PLAN_TEST_MODULES;
test('actual ClientModuleSystem registers replacement factory and owns styles across reload', {
  skip: !runtime || !dependencies,
}, async () => {
  const require = createRequire(join(dependencies, 'package.json'));
  const ts = require('typescript');
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<!doctype html><head></head><body></body>');
  const context = vm.createContext({ document: dom.window.document, window: dom.window, console, crypto: webcrypto });
  const cache = new Map();
  const clientRoot = join(runtime, 'packages/client/modules/src/client');
  async function load(relative) {
    const file = resolve(clientRoot, relative);
    if (cache.has(file)) return cache.get(file);
    const text = await readFile(file, 'utf8');
    const code = ts.transpileModule(text, {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    }).outputText;
    const imported = new Map();
    for (const match of code.matchAll(/require\("(\.\/[^\"]+)"\)/g)) {
      imported.set(match[1], await load(join(dirname(relative), match[1])));
    }
    const module = { exports: {} };
    const evaluate = vm.runInContext(`(function(require, module, exports) {\n${code}\n})`, context);
    evaluate(specifier => {
      assert.ok(imported.has(specifier), `Unexpected dependency ${specifier}`);
      return imported.get(specifier);
    }, module, module.exports);
    cache.set(file, module.exports);
    return module.exports;
  }
  const { ClientModuleSystem } = await load('system.ts');
  const { removeOwnedStyles } = await load('entry-lifecycle.ts');
  const { parseDshClient } = await load('manifest.ts');
  const declaration = parseDshClient(replacementPlanPackage, transformed.manifest.dsh.client);
  assert.deepEqual(Array.from(declaration.inject), originalManifest.dsh.client.inject);
  const calls = [];
  const target = { mode: 'queue', pendingQueue: [], load(value) { this.pendingQueue.push(value); } };
  dom.window.__ModuleLoader__ = target;
  const seed = {
    '@deepseek-ai/dsh-client-ui-primitives': {},
    '@deepseek-ai/cordis': {},
    '@deepseek-ai/dsh-client-store': { defineStore: value => value },
    'react/jsx-runtime': { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }) },
    react: { useState: value => [value, () => {}], useRef: value => ({ current: value }), useEffect: () => {} },
  };
  const row = {
    id: replacementPlanPackage,
    url: `plugins/??${replacementPlanPackage}/client.js&rev=one`,
    initialUrl: `plugins/??${replacementPlanPackage}/client.js&rev=one`,
    rev: 'one', inject: declaration.inject, external: declaration.external ?? [],
  };
  const system = new ClientModuleSystem({
    manifest: { rev: 'one', modules: [row], plugins: [{ id: row.id, inject: row.inject, immediately: false }] },
    registrationTarget: target,
    bootstrapModule: { id: '@deepseek-ai/dsh-client-modules', exports: {} },
    staticModules: seed,
    loadBundle: async url => { calls.push(url); vm.runInContext(transformed.client, context); },
  });
  const plugin = await system.import(`${replacementPlanPackage}/client`);
  assert.equal(typeof plugin.apply, 'function');
  const record = system.loadCache.get(replacementPlanPackage);
  assert.deepEqual(Array.from(record.styles).sort(), [
    `${replacementPlanPackage}/PlanModeControl.module.css`,
    `${replacementPlanPackage}/PlanPreview.module.css`,
  ]);
  assert.equal(dom.window.document.querySelectorAll('style').length, 2);
  assert.throws(() => vm.runInContext(transformed.client, context), /duplicate factory registration/);
  await assert.rejects(system.import(originalPlanPackage), /cannot resolve/);
  const cleanups = [];
  const slots = [];
  const commands = [];
  const catalog = new Map();
  let language = 'en';
  const ctx = {
    effect(callback) { cleanups.push(callback()); },
    locale: {
      register(ns, dictionaries) {
        assert.equal(catalog.has(ns), false);
        catalog.set(ns, dictionaries);
        return () => catalog.delete(ns);
      },
      bind: ns => key => catalog.get(ns)[language][key],
    },
    remote: { session: {}, commands: { execute: async (...args) => {
      commands.push(args);
      return { ok: true, value: { matched: true } };
    } } },
    sessions: {},
    uiConversation: { events: { register: () => () => {} } },
    resources: { register: () => () => {} },
    sidebarRight: { mounted: {} },
    sidebarRightTabs: { register: options => {
      assert.equal(options.id, originalPlanPackage);
      return () => {};
    } },
    slots: { inject: (_name, callback) => callback(), register: (options, component) => {
      slots.push({ options, component });
      return () => {};
    } },
  };
  plugin.apply(ctx);
  assert.equal(slots.length, 5);
  const chip = slots.find(slot => slot.options.name === 'conversation.input.plan').component;
  for (const locale of ['en', 'zh']) {
    language = locale;
    const rendered = chip({ useProjection: () => ({ active: true, pending: false }), locked: false, t: ctx.locale.bind('plan') });
    assert.equal(rendered.props.children[0].props.title, planTooltips[locale].corrected);
    assert.equal(rendered.props.children[0].props.disabled, false);
  }
  const injected = slots.find(slot => slot.options.name === 'conversation.input.plan').options.inject('session-fixture');
  assert.equal(await injected.exitPlanMode(), null);
  assert.deepEqual(JSON.parse(JSON.stringify(commands)), [['session-fixture', '/plan off', []]]);
  for (const cleanup of cleanups.reverse()) cleanup();
  assert.equal(catalog.size, 0);
  removeOwnedStyles(replacementPlanPackage);
  assert.equal(dom.window.document.querySelectorAll('style').length, 0);
  system.invalidate(replacementPlanPackage, 'two');
  const reloaded = await system.import(replacementPlanPackage);
  assert.notEqual(reloaded, plugin);
  assert.equal(calls.length, 2);
  assert.match(calls[1], /rev=two$/);
  assert.equal(dom.window.document.querySelectorAll('style').length, 2);
  removeOwnedStyles(replacementPlanPackage);
  dom.window.close();
});
