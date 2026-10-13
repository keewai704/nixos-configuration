import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('./client.js', import.meta.url), 'utf8');

function capture(react = {}) {
  let plugin;
  const context = vm.createContext({ window: { __ModuleLoader__: { load(value) { plugin = value; } } } });
  vm.runInContext(source, context);
  assert.equal(plugin.id, '@keewai/dsh-operations');
  return { context, plugin: plugin.factory(name => { assert.equal(name, 'react'); return react; }) };
}

test('client registers an additive page and Japanese fallback without React duplication', () => {
  const { plugin } = capture();
  const dictionaries = new Map();
  const pages = [];
  const cleanups = [];
  const locale = {
    addLanguage: language => { assert.deepEqual(JSON.parse(JSON.stringify(language)), { id: 'ja', label: '日本語', fallback: 'en' }); return () => {}; },
    register: (ns, language, dict) => {
      dictionaries.set(ns, typeof language === 'string' ? { [language]: dict } : language);
      return () => dictionaries.delete(ns);
    },
    bind: ns => key => dictionaries.get(ns).en[key],
  };
  plugin.apply({
    locale, effect: callback => cleanups.push(callback()),
    slots: { inject: (_name, callback) => callback(), register: (options, component) => { pages.push({ options, component }); return () => {}; } },
  });
  assert.equal(pages[0].options.name, 'settings.section');
  assert.equal(pages[0].options.id, 'operations');
  assert.equal(pages[0].options.label(), 'Privacy & operations');
  assert.deepEqual(Object.keys(dictionaries.get('operations').en).sort(), Object.keys(dictionaries.get('operations').ja).sort());
  assert.equal(dictionaries.get('common').ja.save, '保存');
  for (const cleanup of cleanups.reverse()) cleanup();
  assert.equal(dictionaries.size, 0);
});

test('client loads status, previews retention and requires exact mutation confirmation', async () => {
  assert.ok(process.env.DSH_CLIENT_TEST_MODULES, 'Set DSH_CLIENT_TEST_MODULES to a disposable React/jsdom dependency directory');
  const require = createRequire(`${process.env.DSH_CLIENT_TEST_MODULES}/package.json`);
  const React = require('react');
  const { createRoot } = require('react-dom/client');
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<div id="root"></div>', { url: 'https://dsh.invalid/' });
  const old = { window: globalThis.window, document: globalThis.document, act: globalThis.IS_REACT_ACT_ENVIRONMENT };
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const { context, plugin } = capture(React);
  const calls = [];
  const status = {
    persistence: 'launch-reset',
    privacy: [{ id: 'session-log-deepseek', effective: 'enabled', editable: true, revision: 'r1', scope: 'Scope' }],
    inventory: { entries: [{ id: 'broken', module: 'fixture', phase: 'failed' }], bundles: [] }, reliability: { workflowJournal: false },
  };
  Object.assign(context, { URL, AbortController, document: dom.window.document, fetch: async (url, options) => {
    calls.push({ url: url.href, options });
    const result = url.pathname.endsWith('recovery') ? { application: 'failed', error: { code: 'management-required' } }
      : url.pathname.endsWith('retention') ? { candidates: [], totalSessions: 1, candidateBytes: 0 } : status;
    return { ok: true, json: async () => result };
  } });
  const dictionaries = new Map();
  let Page;
  const snapshot = { active: 'en', revision: 0 };
  plugin.apply({
    effect: callback => callback(),
    locale: {
      addLanguage: () => () => {}, register: (ns, lang, value) => { dictionaries.set(ns, value ? { [lang]: value } : lang); return () => {}; },
      bind: ns => key => dictionaries.get(ns).en[key], subscribe: () => () => {}, getSnapshot: () => snapshot,
    },
    slots: { inject: (_name, callback) => callback(), register: (_options, component) => { Page = component; return () => {}; } },
  });
  const root = createRoot(dom.window.document.getElementById('root'));
  const click = async label => {
    const button = [...dom.window.document.querySelectorAll('button')].find(node => node.textContent === label);
    assert.ok(button, `Missing ${label}`);
    await React.act(async () => button.click());
  };
  try {
    await React.act(async () => root.render(React.createElement(Page)));
    assert.equal(calls[0].url, 'https://dsh.invalid/api/operations/status');
    await click('Disable…');
    const confirm = [...dom.window.document.querySelectorAll('button')].find(node => node.textContent === 'Confirm change');
    assert.equal(confirm.disabled, true);
    assert.match(dom.window.document.querySelector('[role="group"]').textContent, /Nix-managed/);
    assert.match(dom.window.document.querySelector('[role="group"]').textContent, /next launch or regeneration/);
    assert.equal(calls.filter(row => row.options.method === 'POST').length, 0);
    await click('Cancel');
    await click('Preview only');
    const preview = calls.find(row => row.url.endsWith('/retention'));
    assert.equal(preview.options.headers['x-dsh-operations'], '1');
    assert.equal(JSON.parse(preview.options.body).days, 365);
    assert.equal(dom.window.document.querySelector('[role="alert"]'), null);
    await click('Disable failed entry…');
    const input = dom.window.document.querySelector('input:not([type="number"])');
    const { Simulate } = require('react-dom/test-utils');
    await React.act(async () => Simulate.change(input, { target: { value: 'DISABLE broken' } }));
    await click('Confirm change');
    assert.match(dom.window.document.querySelector('[role="alert"]').textContent, /management-required/);
    assert.ok(dom.window.document.querySelector('[role="group"]'), 'failed confirmation remains visible');
    assert.equal(dom.window.document.querySelector('input:not([type="number"])').value, 'DISABLE broken');
  } finally {
    await React.act(async () => root.unmount());
    dom.window.close();
    globalThis.window = old.window;
    globalThis.document = old.document;
    globalThis.IS_REACT_ACT_ENVIRONMENT = old.act;
  }
});
