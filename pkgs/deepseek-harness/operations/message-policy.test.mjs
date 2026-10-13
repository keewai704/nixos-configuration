import test from 'node:test';
import assert from 'node:assert/strict';
import { apply, rewriteAssembly, rewriteShellContent, CLIPPED_ADVICE, SEARCH_SCOPE, PLAN_SCOPE } from './message-policy.mjs';

const old = '<response clipped><NOTE>To save on context only part of this file has been shown to you. You should retry this tool after you have searched inside the file with `grep -n` in order to find the line numbers of what you are looking for.</NOTE>';

test('only a known shell suffix is changed, never command text in the middle', () => {
  const content = [{ type: 'text', text: `prefix\n${old}` }, { type: 'text', text: `${old} not suffix` }, { type: 'image', url: 'safe' }];
  const result = rewriteShellContent(content);
  assert.equal(result[0].text, `prefix\n${CLIPPED_ADVICE}`);
  assert.equal(result[1], content[1]);
  assert.equal(result[2], content[2]);
  assert.equal(content[0].text, `prefix\n${old}`);
});

test('prompt policy rewrites selected schema descriptions and only the owned grep section', () => {
  const original = { sections: [{ name: 'tool:grep', text: 'Use read on a matched file when you need surrounding context.' }, { name: 'deployment:persona-prefix', text: 'Use read on a matched file when you need surrounding context.' }], tools: ['grep', 'glob', 'exit_plan_mode', 'other'].map(name => ({ name, description: name })), contexts: [], variables: {} };
  const changed = rewriteAssembly(original);
  assert.match(changed.sections[0].text, /same filesystem/);
  assert.equal(changed.sections[1], original.sections[1]);
  assert.ok(changed.tools[0].description.endsWith(SEARCH_SCOPE));
  assert.ok(changed.tools[2].description.endsWith(PLAN_SCOPE));
  assert.equal(changed.tools[3], original.tools[3]);
  assert.deepEqual(rewriteAssembly(changed), changed);
  assert.equal(original.tools[0].description, 'grep');
});

test('middleware preserves downstream denial, canonical value, and non-shell results', async () => {
  const handlers = new Map(); apply({ on: (event, handler) => handlers.set(event, handler) });
  const post = handlers.get('tools/post-execute');
  const result = { isError: false, value: { unchanged: true }, content: [{ type: 'text', text: old }] };
  const blocked = { kind: 'block', feedback: [] };
  assert.equal(await post({ name: 'bash' }, result, async () => blocked), blocked);
  const value = { kind: 'accept', value: {} };
  assert.equal(await post({ name: 'bash' }, result, async () => value), value);
  const accept = { kind: 'accept', additionalContexts: [] };
  assert.equal(await post({ name: 'read' }, result, async () => accept), accept);
  const changed = await post({ name: 'bash' }, result, async () => accept);
  assert.equal(changed.content[0].text, CLIPPED_ADVICE);
  assert.equal(changed.additionalContexts, accept.additionalContexts);
  assert.equal(Object.hasOwn(changed, 'value'), false);
  assert.deepEqual(result.value, { unchanged: true });
});
