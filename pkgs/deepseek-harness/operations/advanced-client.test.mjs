import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import * as advanced from './advanced-client.js';

const { createAdvancedOperations } = advanced;

const require = process.env.DSH_CLIENT_TEST_MODULES
  ? createRequire(`${process.env.DSH_CLIENT_TEST_MODULES}/package.json`)
  : createRequire(import.meta.url);
const React = require('react');
const { createRoot } = require('react-dom/client');
const { Simulate } = require('react-dom/test-utils');
const { JSDOM } = require('jsdom');
const clone = value => structuredClone(value);
const route = { provider: 'operator-provider', model: 'operator-model', prompt: 'User-written task', deps: [], id: 'first' };
const graph = { nodes: [route] };
const rootId = 'root /?&日本語';
const identity = 'live-root-identity';
const makeDelivery = (changes = {}) => ({
  id: 'delivery-original', sessionId: rootId, revision: 'opaque-row-revision', attempts: 5, totalAttempts: 10, recoveryCount: 1,
  retryAt: 1700000000000, inFlight: false, retryable: true,
  members: [{ taskId: 'schedule-original', scheduledAt: 1700000000000, nextScheduledAt: 1700000100000 }],
  ...changes,
});
const makeRun = (changes = {}) => ({
  id: 'owned', rootId, status: 'draft', revision: 2,
  nodes: [{ ...route, promptPreview: 'private prompt must not render', result: { text: 'private result must not render' }, status: 'pending', attempt: 1, attempts: [] }],
  ...changes,
});
const makeBudget = (changes = {}) => ({
  rootSessionId: rootId, revision: 7, limits: { maxRequests: 20 }, requests: 3, children: 1,
  activeChildren: 1, ambiguousChildren: 1, ambiguousRequests: 2, unknownCostRequests: 2,
  reserved: { outputTokens: 400, costMicros: 60 }, usage: { outputTokens: 12, costMicros: null },
  accountedOutputTokens: 12, accountedCostMicros: 0,
  requestRecords: [
    { id: 'request-z', root_id: rootId, state: 'ambiguous', output_reserved: 200, cost_reserved: 30 },
    { id: 'request-a', root_id: rootId, state: 'ambiguous', output_reserved: 200, cost_reserved: 30 },
    { id: 'already-measured', root_id: rootId, state: 'measured' },
    { id: 'other-request', root_id: 'other', state: 'ambiguous' },
  ],
  childRecords: [{ id: 'child-reservation', child_id: 'actual-child-session', root_id: rootId, state: 'ambiguous' }],
  ...changes,
});
function fixtures() {
  const state = {
    listing: { roots: [{ id: rootId, identity }, { id: 'other', identity: 'other-identity' }], runs: [
      { id: 'owned', rootId, status: 'draft', revision: 2 },
      { id: 'not-owned', rootId: 'other', status: 'draft', revision: 1 },
      { id: 'prefix-impostor', rootId: `${rootId}-suffix`, status: 'draft', revision: 1 },
    ] },
    run: makeRun(), budget: makeBudget(), deliveries: [makeDelivery()],
    capabilities: { limits: ['maxRequests', 'maxChildren'], outputCaps: ['deepseek-official'], cost: 'unknown billing is never zero', totalInputCap: false },
  };
  state.api = async (path, body) => {
    if (path === 'checkpoints') return clone(state.listing);
    if (path.startsWith('checkpoints?')) return clone(state.run);
    if (path === 'budgets') return { capabilities: clone(state.capabilities), roots: [clone(state.budget)] };
    if (path === 'deliveries') return { version: 1, obligations: clone(state.deliveries) };
    if (path === 'deliveries/retry') {
      const obligation = state.deliveries.find(row => row.id === body.id);
      Object.assign(obligation, { revision: 'next-opaque-revision', attempts: 0, recoveryCount: obligation.recoveryCount + 1, retryable: false });
      return { obligation: clone(obligation) };
    }
    if (path === 'checkpoints/action') {
      if (body.action === 'create') state.run = makeRun({ id: body.id, status: 'draft', revision: 1 });
      else state.run = makeRun({ ...state.run, revision: state.run.revision + 1, status: body.action === 'cancel' ? 'cancelled' : body.action === 'retry' ? 'paused' : 'running' });
      state.listing.runs = [{ id: state.run.id, rootId, status: state.run.status, revision: state.run.revision }];
      return { ...clone(state.run), authorization: { actor: 'authenticated-operator', action: body.action, rootId, priorRevision: body.revision ?? null, confirmation: body.confirmation } };
    }
    if (path === 'budgets/configure') state.budget = makeBudget({ ...state.budget, limits: clone(body.limits), revision: state.budget.revision + 1 });
    else if (path === 'budgets/reconcile') state.budget = makeBudget({ ...state.budget, revision: state.budget.revision + 1,
      requestRecords: state.budget.requestRecords.map(row => body.requestIds.includes(row.id) ? { ...row, state: 'charged' } : row),
      childRecords: state.budget.childRecords.map(row => body.childIds.includes(row.id) ? { ...row, state: 'settled' } : row),
    });
    else throw new Error(`Unexpected mock API call ${path}`);
    return clone(state.budget);
  };
  return state;
}
async function mount(t, { api, locale = 'en', strict = false } = {}) {
  const dom = new JSDOM('<div id="root"></div>', { url: 'https://dsh.invalid/' });
  const previous = Object.fromEntries(['window', 'document', 'IS_REACT_ACT_ENVIRONMENT'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  Object.assign(globalThis, { window: dom.window, document: dom.window.document, IS_REACT_ACT_ENVIRONMENT: true });
  const calls = [];
  const state = fixtures();
  const Component = createAdvancedOperations(React, async (path, body, signal) => {
    calls.push({ path, body: body === undefined ? undefined : clone(body), signal });
    return (api ?? state.api)(path, body, signal);
  });
  const renderer = createRoot(dom.window.document.getElementById('root'));
  let active = true;
  const unmount = async () => { if (active) { active = false; await React.act(async () => renderer.unmount()); } };
  t.after(async () => {
    await unmount(); dom.window.close();
    for (const [key, descriptor] of Object.entries(previous)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key];
    }
  });
  await React.act(async () => renderer.render(strict ? React.createElement(React.StrictMode, null, React.createElement(Component, { locale })) : React.createElement(Component, { locale })));
  const document = dom.window.document;
  const button = label => {
    const node = [...document.querySelectorAll('button')].find(element => element.textContent === label);
    assert.ok(node, `Missing button ${label}`); return node;
  };
  const field = label => {
    const node = [...document.querySelectorAll('[aria-label]')].find(element => element.getAttribute('aria-label') === label);
    assert.ok(node, `Missing field ${label}`); return node;
  };
  const change = async (label, value) => React.act(async () => Simulate.change(field(label), { target: { value } }));
  const click = async label => React.act(async () => button(label).click());
  const check = async (label, checked = true) => {
    const node = [...document.querySelectorAll('label')].find(element => element.textContent.trim() === label)?.querySelector('input[type="checkbox"]');
    assert.ok(node, `Missing checkbox ${label}`);
    await React.act(async () => Simulate.change(node, { target: { checked } }));
  };
  const load = async () => { await click('Load controls'); await change('Live checkpoint root', rootId); };
  const selectRun = async () => { await load(); await change('Owned checkpoint run', 'owned'); await click('Load selected run details'); };
  const selectBudget = async () => { await click('Load controls'); await change('Live budget root', rootId); };
  return { state, calls, document, button, field, change, click, check, load, selectRun, selectBudget, unmount, posts: () => calls.filter(call => call.body !== undefined) };
}

test('factory is standalone and embeddable without imports or surrounding helpers', () => {
  const source = readFileSync(new URL('./advanced-client.js', import.meta.url), 'utf8');
  const embedded = `${source.replace('export function createAdvancedOperations', 'function createAdvancedOperations')}\ncreateAdvancedOperations;`;
  const factory = vm.runInNewContext(embedded, { URLSearchParams, TextEncoder, AbortController });
  assert.equal(typeof factory, 'function');
  assert.equal(factory(React, () => {}).name, 'AdvancedOperations');
  assert.deepEqual(Object.keys(advanced), ['createAdvancedOperations']);
});

test('opening even in StrictMode does not fetch or mutate; load selects only exact owned root runs', async t => {
  const ui = await mount(t, { strict: true });
  assert.equal(ui.calls.length, 0);
  assert.match(ui.document.body.textContent, /not cryptographic proof/);
  assert.match(ui.document.body.textContent, /including never, is unchanged/);
  await ui.load();
  assert.deepEqual(ui.calls.map(call => call.path), ['checkpoints', 'budgets', 'deliveries']);
  assert.equal(ui.posts().length, 0);
  assert.deepEqual([...ui.field('Owned checkpoint run').options].map(option => option.value), ['', 'owned']);
  assert.equal(ui.field('Graph JSON').value, '');
  assert.equal(ui.button('Create draft only').disabled, true);
  await ui.change('Owned checkpoint run', 'owned');
  assert.equal(ui.calls.length, 3, 'selecting a run does not automatically fetch');
  await ui.click('Load selected run details');
  const query = new URL(`https://dsh.invalid/${ui.calls.at(-1).path}`).searchParams;
  assert.equal(query.get('id'), 'owned');
  assert.equal(query.get('ownerSessionId'), rootId);
  assert.equal(query.get('ownerIdentity'), identity);
  assert.match(ui.calls.at(-1).path, /%26/);
  assert.doesNotMatch(ui.document.body.textContent, /private prompt must not render|private result must not render/);
});

test('draft creation requires exact typed confirmation and never starts; receipt metadata is shown', async t => {
  const ui = await mount(t);
  await ui.load();
  await ui.change('New checkpoint ID', 'operator-draft');
  await ui.change('Graph JSON', JSON.stringify(graph));
  await ui.click('Create draft only');
  assert.equal(ui.posts().length, 0);
  await ui.change('Draft confirmation', `CREATE CHECKPOINT ${rootId} 0 `);
  assert.equal(ui.button('Create draft only').disabled, true);
  await ui.change('Draft confirmation', `CREATE CHECKPOINT ${rootId} 0`);
  await ui.click('Create draft only');
  assert.equal(ui.posts().length, 1);
  assert.deepEqual(ui.posts()[0].body, { action: 'create', ownerSessionId: rootId, ownerIdentity: identity, id: 'operator-draft', graph, confirmation: `CREATE CHECKPOINT ${rootId} 0` });
  assert.match(ui.document.body.textContent, /Draft saved; not started/);
  assert.match(ui.document.body.textContent, /authenticated-operator/);
  assert.equal(ui.field('Checkpoint action').value, '');
  assert.equal(ui.field('Draft confirmation').value, '');
  assert.equal(ui.calls.filter(call => call.body?.action === 'start').length, 0);
});

test('graph errors are accessible and total UTF-8 POST payload is bounded to 32 KiB', async t => {
  const ui = await mount(t);
  await ui.load();
  await ui.change('New checkpoint ID', 'large-draft');
  for (const [value, message] of [
    ['[]', /JSON object/],
    [JSON.stringify({ nodes: [{ id: 'first', deps: [], model: 'manually-entered', prompt: 'task' }] }), /explicit valid/],
    [JSON.stringify({ nodes: [{ ...route, prompt: '日'.repeat(12000) }] }), /32 KiB/],
  ]) {
    await ui.change('Graph JSON', value);
    await ui.change('Draft confirmation', `CREATE CHECKPOINT ${rootId} 0`);
    await ui.click('Create draft only');
    assert.match(ui.document.querySelector('[role="alert"]').textContent, message);
    assert.equal(ui.posts().length, 0);
    assert.equal(ui.field('Draft confirmation').value, `CREATE CHECKPOINT ${rootId} 0`);
  }
});

test('failed action retains confirmation and requires refresh plus new revision with no replay', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: async (path, body, signal) => {
    if (body) { state.run.revision = 9; state.listing.runs[0].revision = 9; throw new Error('revision changed'); }
    return state.api(path, body, signal);
  } });
  await ui.selectRun();
  await ui.change('Checkpoint action', 'start');
  await ui.change('Action confirmation', 'START CHECKPOINT owned 2');
  await ui.click('Submit checkpoint action');
  assert.equal(ui.posts().length, 1);
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /revision changed/);
  assert.equal(ui.field('Action confirmation').value, 'START CHECKPOINT owned 2');
  assert.equal(ui.button('Submit checkpoint action').disabled, true);
  await ui.click('Submit checkpoint action');
  await ui.click('Refresh controls');
  assert.equal(ui.posts().length, 1);
  assert.match(ui.document.body.textContent, /START CHECKPOINT owned 9/);
  assert.equal(ui.field('Action confirmation').value, 'START CHECKPOINT owned 2');
  assert.equal(ui.button('Submit checkpoint action').disabled, true);
  await ui.change('Action confirmation', 'START CHECKPOINT owned 9');
  assert.equal(ui.button('Submit checkpoint action').disabled, false);
});

test('start, resume and cancel send only exact current operator metadata', async t => {
  const ui = await mount(t);
  await ui.selectRun();
  for (const [action, status] of [['start', 'draft'], ['resume', 'paused'], ['cancel', 'running']]) {
    ui.state.run.status = status;
    await ui.click('Refresh controls');
    await ui.change('Checkpoint action', action);
    const confirmation = `${action.toUpperCase()} CHECKPOINT owned ${ui.state.run.revision}`;
    await ui.change('Action confirmation', confirmation.toLowerCase());
    assert.equal(ui.button('Submit checkpoint action').disabled, true);
    await ui.change('Action confirmation', confirmation);
    const before = ui.posts().length;
    const currentRevision = ui.state.run.revision;
    await ui.click('Submit checkpoint action');
    assert.equal(ui.posts().length, before + 1);
    assert.deepEqual(ui.posts().at(-1).body, { action, ownerSessionId: rootId, ownerIdentity: identity, id: 'owned', revision: currentRevision, confirmation });
  }
});

test('retry requires two exact phrases and never resumes automatically', async t => {
  const ui = await mount(t);
  ui.state.run = makeRun({ status: 'ambiguous', revision: 11, nodes: [{ ...route, status: 'ambiguous', attempt: 3, attempts: [{ attempt: 3, status: 'ambiguous', childId: 'possibly-live-child' }] }] });
  await ui.selectRun();
  await ui.change('Checkpoint action', 'retry');
  await ui.change('Failed or ambiguous node', 'first');
  await ui.change('Action confirmation', 'RETRY CHECKPOINT owned 11');
  assert.equal(ui.button('Submit checkpoint action').disabled, true);
  await ui.change('Retry confirmation', 'RETRY owned/first/3 @11 ');
  assert.equal(ui.button('Submit checkpoint action').disabled, true);
  await ui.change('Retry confirmation', 'RETRY owned/first/3 @11');
  await ui.click('Submit checkpoint action');
  assert.deepEqual(ui.posts()[0].body, { action: 'retry', ownerSessionId: rootId, ownerIdentity: identity, id: 'owned', revision: 11, confirmation: 'RETRY CHECKPOINT owned 11', nodeId: 'first', attempt: 3, retryConfirmation: 'RETRY owned/first/3 @11' });
  assert.match(ui.document.body.textContent, /New pending attempt prepared; not resumed/);
  assert.equal(ui.posts().length, 1);
});

test('root identity changes invalidate checkpoint selection and typed authorization', async t => {
  const ui = await mount(t);
  await ui.selectRun();
  await ui.change('Checkpoint action', 'start');
  await ui.change('Action confirmation', 'START CHECKPOINT owned 2');
  ui.state.listing.roots[0].identity = 'new-session-identity';
  await ui.click('Refresh controls');
  assert.equal(ui.field('Live checkpoint root').value, '');
  assert.equal(ui.posts().length, 0);
  assert.equal(ui.document.querySelector('[aria-label="Action confirmation"]'), null);
});

test('budget configuration requires exact phrase and accepts only advertised integer limit keys', async t => {
  const ui = await mount(t);
  await ui.selectBudget();
  assert.match(ui.document.body.textContent, /Claude has no supported hard output\/cost guarantee/);
  assert.match(ui.document.body.textContent, /Unknown pricing is not zero/);
  assert.match(ui.document.body.textContent, /"costMicros": null/);
  assert.match(ui.document.body.textContent, /omitted limits are removed/);
  assert.equal(ui.button('Apply budget limits').disabled, true);
  for (const value of ['{"maxCostMicros":20}', '{"maxRequests":-1}', '{"maxRequests":1.5}', '{"maxRequests":"2"}', '{"maxRequests":9007199254740992}']) {
    await ui.change('Replacement limits JSON', value);
    await ui.change('Budget confirmation', `BUDGET ${rootId} 7`);
    await ui.click('Apply budget limits');
    assert.match(ui.document.querySelector('[role="alert"]').textContent, /subset of the advertised/);
    assert.equal(ui.posts().length, 0);
  }
  await ui.change('Replacement limits JSON', '{"maxRequests":4,"maxChildren":0}');
  assert.equal(ui.field('Budget confirmation').value, '');
  await ui.change('Budget confirmation', `BUDGET ${rootId} 7 `);
  assert.equal(ui.button('Apply budget limits').disabled, true);
  await ui.change('Budget confirmation', `BUDGET ${rootId} 7`);
  await ui.click('Apply budget limits');
  assert.deepEqual(ui.posts()[0].body, { rootSessionId: rootId, revision: 7, limits: { maxRequests: 4, maxChildren: 0 }, confirmation: `BUDGET ${rootId} 7` });
  assert.match(ui.document.body.textContent, /Budget configuration accepted by the server/);
  assert.equal(ui.field('Budget confirmation').value, '');
});

test('budget failure retains text; refresh exposes latest revision without replay', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: async (path, body, signal) => {
    if (body) { state.budget.revision = 8; throw new Error('budget revision changed'); }
    return state.api(path, body, signal);
  } });
  await ui.selectBudget();
  await ui.change('Budget confirmation', `BUDGET ${rootId} 7`);
  await ui.click('Apply budget limits');
  assert.equal(ui.field('Budget confirmation').value, `BUDGET ${rootId} 7`);
  assert.equal(ui.button('Apply budget limits').disabled, true);
  await ui.click('Refresh controls');
  assert.match(ui.document.body.textContent, new RegExp(`BUDGET ${rootId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} 8`));
  assert.equal(ui.field('Budget confirmation').value, `BUDGET ${rootId} 7`);
  assert.equal(ui.posts().length, 1);
  assert.equal(ui.button('Apply budget limits').disabled, true);
});

test('reconciliation uses ambiguous reservation IDs, sorted exact phrase and explicit quiescence, never zeroes charge', async t => {
  const ui = await mount(t);
  await ui.selectBudget();
  assert.match(ui.document.body.textContent, /independently verify execution quiescence/);
  assert.match(ui.document.body.textContent, /FULL reserved output\/cost charge/);
  const checks = [...ui.document.querySelectorAll('input[type="checkbox"]')];
  assert.equal(checks.every(node => !node.checked), true);
  assert.doesNotMatch(ui.document.body.textContent, /other-request|already-measured/);
  await ui.check('Request reservation: request-z');
  await ui.check('Request reservation: request-a');
  await ui.check('Child reservation: child-reservation (child_id: actual-child-session)');
  const confirmation = `RECONCILE ${rootId} 7 request-a,request-z child-reservation`;
  await ui.change('Reconciliation confirmation', confirmation);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  await ui.check('I independently verified execution quiescence for every selected reservation');
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, false);
  await ui.click('Reconcile with full reserved charge');
  assert.deepEqual(ui.posts()[0].body, { rootSessionId: rootId, revision: 7, requestIds: ['request-a', 'request-z'], childIds: ['child-reservation'], confirmation });
  assert.equal('cost' in ui.posts()[0].body, false);
  assert.equal('usage' in ui.posts()[0].body, false);
  assert.match(ui.document.body.textContent, /unknown billing remains unknown/);
  assert.equal(ui.posts().length, 1);
});

test('request-only reconciliation preserves the required trailing space and resets quiescence on refresh', async t => {
  const ui = await mount(t);
  await ui.selectBudget();
  await ui.check('Request reservation: request-z');
  await ui.check('I independently verified execution quiescence for every selected reservation');
  await ui.change('Reconciliation confirmation', `RECONCILE ${rootId} 7 request-z`);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  const confirmation = `RECONCILE ${rootId} 7 request-z `;
  await ui.change('Reconciliation confirmation', confirmation);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, false);
  await ui.click('Refresh controls');
  assert.equal(ui.field('Reconciliation confirmation').value, confirmation);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  await ui.check('I independently verified execution quiescence for every selected reservation');
  await ui.click('Reconcile with full reserved charge');
  assert.equal(ui.posts()[0].body.confirmation, confirmation);
  assert.deepEqual(ui.posts()[0].body.childIds, []);
});

test('reconciliation failure retains confirmation and refresh requires a new revision and fresh quiescence check', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: async (path, body, signal) => {
    if (body) { state.budget.revision = 10; throw new Error('reconciliation outcome uncertain'); }
    return state.api(path, body, signal);
  } });
  await ui.selectBudget();
  await ui.check('Child reservation: child-reservation (child_id: actual-child-session)');
  await ui.check('I independently verified execution quiescence for every selected reservation');
  const confirmation = `RECONCILE ${rootId} 7  child-reservation`;
  await ui.change('Reconciliation confirmation', confirmation);
  await ui.click('Reconcile with full reserved charge');
  assert.equal(ui.field('Reconciliation confirmation').value, confirmation);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  await ui.click('Refresh controls');
  assert.equal(ui.posts().length, 1);
  assert.equal(ui.field('Reconciliation confirmation').value, confirmation);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  assert.ok(ui.document.body.textContent.includes(`RECONCILE ${rootId} 10  child-reservation`));
  await ui.change('Reconciliation confirmation', `RECONCILE ${rootId} 10  child-reservation`);
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  await ui.check('I independently verified execution quiescence for every selected reservation');
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, false);
});

test('both the 100-record selection limit and complete reconciliation payload byte limit are enforced', async t => {
  const ui = await mount(t);
  ui.state.budget.childRecords = [];
  ui.state.budget.requestRecords = Array.from({ length: 101 }, (_, index) => ({ id: `r${index}-${'x'.repeat(600)}`, root_id: rootId, state: 'ambiguous' }));
  await ui.selectBudget();
  const boxes = [...ui.document.querySelectorAll('input[type="checkbox"]')].slice(0, 101);
  await React.act(async () => {
    for (const node of boxes) Simulate.change(node, { target: { checked: true } });
  });
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  assert.equal(boxes.every(node => node.checked), true);
  await ui.check('I independently verified execution quiescence for every selected reservation');
  const phrase = ids => `RECONCILE ${rootId} 7 ${ids.sort().join(',')} `;
  await ui.change('Reconciliation confirmation', phrase(ui.state.budget.requestRecords.map(row => row.id)));
  assert.equal(ui.button('Reconcile with full reserved charge').disabled, true);
  await ui.check(`Request reservation: ${ui.state.budget.requestRecords[100].id}`, false);
  await ui.check('I independently verified execution quiescence for every selected reservation');
  await ui.change('Reconciliation confirmation', phrase(ui.state.budget.requestRecords.slice(0, 100).map(row => row.id)));
  await ui.click('Reconcile with full reserved charge');
  assert.equal(ui.posts().length, 0);
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /32 KiB/);
});

test('a missing budget endpoint leaves confirmed checkpoint controls usable and reports the failure', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: (path, body, signal) => {
    if (path === 'budgets') throw new Error('budgets not mounted');
    return state.api(path, body, signal);
  } });
  await ui.load();
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /budgets not mounted/);
  assert.equal(ui.posts().length, 0);
  assert.equal(ui.document.querySelector('[aria-label="Live budget root"]'), null);
  await ui.change('Owned checkpoint run', 'owned');
  await ui.click('Load selected run details');
  await ui.change('Checkpoint action', 'start');
  await ui.change('Action confirmation', 'START CHECKPOINT owned 2');
  assert.equal(ui.button('Submit checkpoint action').disabled, false);
});

test('a mismatched details response is rejected without enabling checkpoint actions', async t => {
  const ui = await mount(t);
  ui.state.run.rootId = 'other';
  await ui.selectRun();
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /Unexpected server response/);
  assert.equal(ui.document.querySelector('[aria-label="Checkpoint action"]'), null);
  assert.equal(ui.posts().length, 0);
});

test('reservation review shows per-record session routes and full charges without private payloads', async t => {
  const ui = await mount(t);
  Object.assign(ui.state.budget.requestRecords[0], {
    session_id: 'request-owner-session', provider: 'route-provider', model: 'route-model', purpose: 'conversation',
    output_reserved: 987, cost_reserved: 654, usage_json: 'private-usage-input', settlement_json: 'private-settlement',
    prompt: 'private-request-prompt', apiKey: 'private-secret',
  });
  Object.assign(ui.state.budget.childRecords[0], { parent_id: 'parent-owner-session', provider: 'child-provider', kind: 'external', prompt: 'private-child-prompt' });
  await ui.selectBudget();
  const text = ui.document.body.textContent;
  for (const value of ['request-owner-session', 'route-provider', 'route-model', 'conversation', '"output_reserved": 987', '"cost_reserved": 654', 'parent-owner-session', 'child-provider', 'external']) assert.ok(text.includes(value), value);
  assert.match(text, /retain this request’s full output_reserved and cost_reserved charge/);
  assert.doesNotMatch(text, /private-usage-input|private-settlement|private-request-prompt|private-secret|private-child-prompt/);
  assert.equal(ui.posts().length, 0);
});

test('delivery retry uses exact opaque revision and original ID only after typed confirmation', async t => {
  const ui = await mount(t);
  assert.equal(ui.calls.length, 0);
  await ui.click('Load controls');
  assert.equal(ui.posts().length, 0);
  await ui.change('Original delivery obligation', 'delivery-original');
  assert.match(ui.document.body.textContent, /same delivery ID and immutable text/);
  assert.match(ui.document.body.textContent, /Input acceptance is not exactly-once/);
  assert.match(ui.document.body.textContent, /at most 5 automatic attempts/);
  assert.match(ui.document.body.textContent, /at most 100 manual recovery generations/);
  assert.equal(ui.button('Retry original delivery').disabled, true);
  await ui.change('Delivery retry confirmation', 'RETRY DELIVERY delivery-original opaque-row-revision ');
  assert.equal(ui.button('Retry original delivery').disabled, true);
  await ui.change('Delivery retry confirmation', 'RETRY DELIVERY delivery-original opaque-row-revision');
  await ui.click('Retry original delivery');
  assert.deepEqual(ui.posts().map(call => ({ path: call.path, body: call.body })), [{ path: 'deliveries/retry', body: { id: 'delivery-original', expectedRevision: 'opaque-row-revision', confirmation: 'RETRY DELIVERY delivery-original opaque-row-revision' } }]);
  assert.equal(ui.calls.length, 4, 'no automatic GET follows the POST');
  assert.match(ui.document.body.textContent, /Reload before any further delivery retry/);
  assert.equal(ui.field('Delivery retry confirmation').value, '');
  assert.equal(ui.button('Retry original delivery').disabled, true);
});

test('delivery retry failure preserves phrase and refresh requires the newest revision with no replay', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: (path, body) => {
    if (path === 'deliveries/retry') { state.deliveries[0].revision = 'updated-row-hash'; throw new Error('delivery revision changed'); }
    return state.api(path, body);
  } });
  await ui.click('Load controls');
  await ui.change('Original delivery obligation', 'delivery-original');
  await ui.change('Delivery retry confirmation', 'RETRY DELIVERY delivery-original opaque-row-revision');
  await ui.click('Retry original delivery');
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /delivery revision changed/);
  assert.equal(ui.field('Delivery retry confirmation').value, 'RETRY DELIVERY delivery-original opaque-row-revision');
  assert.equal(ui.button('Retry original delivery').disabled, true);
  await ui.click('Retry original delivery');
  await ui.click('Refresh controls');
  assert.equal(ui.posts().length, 1);
  assert.ok(ui.document.body.textContent.includes('RETRY DELIVERY delivery-original updated-row-hash'));
  assert.equal(ui.field('Delivery retry confirmation').value, 'RETRY DELIVERY delivery-original opaque-row-revision');
  assert.equal(ui.button('Retry original delivery').disabled, true);
  await ui.change('Delivery retry confirmation', 'RETRY DELIVERY delivery-original updated-row-hash');
  assert.equal(ui.button('Retry original delivery').disabled, false);
});

test('nonretryable, in-flight and accepted delivery snapshots never enable retry', async t => {
  const ui = await mount(t);
  ui.state.deliveries = [
    makeDelivery({ id: 'not-retryable', retryable: false, recoveryCount: 100 }),
    makeDelivery({ id: 'in-flight', inFlight: true }),
    makeDelivery({ id: 'accepted', deliveredAt: 1700000000001 }),
  ];
  await ui.click('Load controls');
  for (const row of ui.state.deliveries) {
    await ui.change('Original delivery obligation', row.id);
    await ui.change('Delivery retry confirmation', `RETRY DELIVERY ${row.id} ${row.revision}`);
    assert.equal(ui.button('Retry original delivery').disabled, true);
    await ui.click('Retry original delivery');
  }
  assert.equal(ui.posts().length, 0);
  assert.match(ui.document.body.textContent, /Native accepted or canceled evidence stops reinsertion/);
});

test('delivery display is bounded and uses safe redacted text, including Japanese labels', async t => {
  const ui = await mount(t, { locale: 'ja' });
  const unsafeId = '<img src=x onerror="globalThis.bad=true">';
  ui.state.deliveries = Array.from({ length: 101 }, (_, index) => makeDelivery({ id: index === 0 ? unsafeId : `delivery-${index}` }));
  Object.assign(ui.state.deliveries[0], { text: 'private-immutable-text', prompt: 'private-delivery-prompt', credential: 'private-delivery-secret' });
  ui.state.deliveries[0].members[0].prompt = 'private-member-prompt';
  await ui.click('操作情報を読み込む');
  assert.equal(ui.field('元の配信義務').options.length, 101);
  assert.equal([...ui.field('元の配信義務').options].some(option => option.value === 'delivery-100'), false);
  await ui.change('元の配信義務', unsafeId);
  assert.equal(ui.document.querySelector('img'), null);
  assert.ok(ui.document.body.textContent.includes(unsafeId));
  assert.doesNotMatch(ui.document.body.textContent, /private-immutable-text|private-delivery-prompt|private-delivery-secret|private-member-prompt/);
  assert.match(ui.document.body.textContent, /新しいリマインダーは作成しません/);
  await ui.change('配信再試行の確認文字列', `RETRY DELIVERY ${unsafeId} opaque-row-revision`);
  assert.equal(ui.button('元の配信を再試行').disabled, false);
  assert.equal(ui.posts().length, 0);
});

test('missing optional delivery API reports error without disabling other controls', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: (path, body) => {
    if (path === 'deliveries') throw new Error('deliveries not mounted');
    return state.api(path, body);
  } });
  await ui.load();
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /deliveries not mounted/);
  assert.equal(ui.document.querySelector('[aria-label="Original delivery obligation"]'), null);
  await ui.change('Owned checkpoint run', 'owned');
  await ui.click('Load selected run details');
  await ui.change('Checkpoint action', 'start');
  await ui.change('Action confirmation', 'START CHECKPOINT owned 2');
  assert.equal(ui.button('Submit checkpoint action').disabled, false);
  await ui.change('Live budget root', rootId);
  await ui.change('Budget confirmation', `BUDGET ${rootId} 7`);
  assert.equal(ui.button('Apply budget limits').disabled, false);
  assert.equal(ui.posts().length, 0);
});

test('Japanese controls have accessible labels and errors without untranslated action UI', async t => {
  const ui = await mount(t, { locale: 'ja' });
  assert.equal(ui.calls.length, 0);
  await ui.click('操作情報を読み込む');
  await ui.change('稼働中のチェックポイントルート', rootId);
  await ui.change('新しいチェックポイントID', 'ja-draft');
  await ui.change('グラフJSON', '{');
  await ui.change('下書き作成の確認文字列', `CREATE CHECKPOINT ${rootId} 0`);
  await ui.click('下書きのみ作成');
  assert.match(ui.document.querySelector('[role="alert"]').textContent, /操作エラー: JSONオブジェクト/);
  assert.equal(ui.posts().length, 0);
  assert.match(ui.document.body.textContent, /人間の操作を暗号学的に証明するものではありません/);
  assert.doesNotMatch(ui.document.body.textContent, /Load controls|Graph JSON|Create draft only/);
});

test('all in-flight load requests abort on disposal and busy disables additional operations', async t => {
  const ui = await mount(t, { api: (_path, _body, signal) => new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  }) });
  await ui.click('Load controls');
  assert.equal(ui.calls.length, 3);
  assert.equal(ui.button('Load controls').disabled, true);
  assert.equal(ui.document.querySelector('section').getAttribute('aria-busy'), 'true');
  await ui.click('Load controls');
  assert.equal(ui.calls.length, 3);
  await ui.unmount();
  assert.equal(ui.calls.every(call => call.signal.aborted), true);
});

test('pending mutation aborts on disposal with no follow-up or repeated POST', async t => {
  const state = fixtures();
  const ui = await mount(t, { api: (path, body, signal) => body ? new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  }) : state.api(path, body, signal) });
  await ui.selectRun();
  await ui.change('Checkpoint action', 'start');
  await ui.change('Action confirmation', 'START CHECKPOINT owned 2');
  await ui.click('Submit checkpoint action');
  assert.equal(ui.posts().length, 1);
  assert.equal(ui.button('Submit checkpoint action').disabled, true);
  assert.equal(ui.field('Action confirmation').disabled, true);
  await ui.click('Submit checkpoint action');
  await ui.unmount();
  assert.equal(ui.posts()[0].signal.aborted, true);
  assert.equal(ui.posts().length, 1);
  assert.equal(ui.calls.length, 5);
});
