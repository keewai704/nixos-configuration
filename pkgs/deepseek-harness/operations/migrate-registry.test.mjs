import assert from 'node:assert/strict';
import { test } from 'node:test';
import { migration, parseJson } from './migrate-registry.mjs';

const legacy = () => ({
  unit: { name: 'session_projcache', version: 3 },
  global: null,
  tables: { sessions: {
    second: { identity: { createdAt: 10, cwd: '/fixture' }, rows: { title: { ver: 1, seq: 7, val: 'stored title' } } },
    first: { identity: { createdAt: 0 }, rows: { opaque: { ver: 2, seq: -1, val: JSON.parse('{"__proto__":{"saved":true},"nested":[null,false,4,"text"]}') } } },
  } },
});

export { legacy };

test('registered pinned migration splits the real whole-unit shape without inventing fold identity', () => {
  const edge = migration('session-projcache-v3-to-v7');
  const input = legacy();
  const original = JSON.stringify(input);
  const files = edge.transform(input);
  assert.deepEqual(files.map(file => file.path), ['storages/session_projcache/sessions/first.json', 'storages/session_projcache/sessions/second.json']);
  for (const file of files) {
    const output = parseJson(file.data);
    edge.validateOutput(output);
    assert.equal(output.version, 7);
    const id = file.path.split('/').at(-1).slice(0, -5);
    assert.deepEqual(output.record, input.tables.sessions[id]);
    assert.equal(Object.hasOwn(output.record.identity, 'formatVersion'), false);
    assert.equal(Object.hasOwn(output.record.identity, 'isSeeded'), false);
  }
  assert.equal(JSON.stringify(input), original);
});

test('registry rejects unknown domains, versions, extensions and unsafe record keys', () => {
  assert.throws(() => migration('third-party-v1-to-v2'), /Unsupported migration/);
  const edge = migration('session-projcache-v3-to-v7');
  for (const modify of [
    doc => { doc.unit.version = 4; },
    doc => { doc.unit.name = 'workspace'; },
    doc => { doc.tables.other = {}; },
    doc => { doc.global = {}; },
    doc => { doc.tables.sessions['../escape'] = doc.tables.sessions.first; },
    doc => { doc.tables.sessions.first.identity.formatVersion = 4; },
    doc => { doc.tables.sessions.first.rows.opaque.seq = -2; },
    doc => { doc.tables.sessions.first.rows.opaque.val = -0; },
    doc => { doc.tables.sessions.first.rows.opaque.val = Infinity; },
  ]) {
    const input = legacy();
    modify(input);
    assert.throws(() => edge.transform(input));
  }
});

test('strict JSON boundary rejects duplicate keys, invalid UTF8, deep input and lossy numbers', () => {
  for (const value of ['{"unit":1,"unit":2}', '{"a":{"x":1,"\\u0078":2}}', '{"n":-0}', '{"n":1e999}', '{"n":9007199254740993}', '['.repeat(130) + '0' + ']'.repeat(130), '{"unterminated":"x}', '{} junk', '[1,]', '{"a":1,}']) {
    assert.throws(() => parseJson(Buffer.from(value)));
  }
  assert.throws(() => parseJson(Buffer.from([0xc0, 0xaf])));
  assert.deepEqual(parseJson(Buffer.from('{"quoted":"[\\\"", "a": [true, false, null, 1.5]}')), { quoted: '["', a: [true, false, null, 1.5] });
});
