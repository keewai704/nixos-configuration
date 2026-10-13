import assert from 'node:assert/strict';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

assert.ok(process.env.DSH_SUBSCRIPTIONS_ROOT);
const { mapResponsesUsage } = await import(pathToFileURL(resolve(process.env.DSH_SUBSCRIPTIONS_ROOT, 'lib/translate/responses.js')));

test('Responses counters preserve exact totals and explicit non-applicable cache writes', () => {
  const value = mapResponsesUsage({ input_tokens: 100, output_tokens: 25, input_tokens_details: { cached_tokens: 80 }, output_tokens_details: { reasoning_tokens: 20 } });
  assert.deepEqual(value, { inputTokens: 20, outputTokens: 25, totalTokens: 125, cacheReadTokens: 80, cacheWriteTokens: 0, reasoningTokens: 20 });
});

test('Responses total remains exact when cached detail is not reported', () => {
  const value = mapResponsesUsage({ input_tokens: 100, output_tokens: 25 });
  assert.equal(value.totalTokens, 125);
  assert.equal(value.cacheWriteTokens, 0);
  assert.equal(Object.hasOwn(value, 'cacheReadTokens'), false);
});

test('Responses total handles zero and rejects unsafe or inconsistent counters', () => {
  assert.equal(mapResponsesUsage({ input_tokens: 0, output_tokens: 0 }).totalTokens, 0);
  for (const usage of [
    { input_tokens: Number.MAX_SAFE_INTEGER, output_tokens: 1 },
    { input_tokens: -1, output_tokens: 10 },
    { input_tokens: 10, output_tokens: 0.5 },
    { input_tokens: 10, output_tokens: 2, input_tokens_details: { cached_tokens: 11 } },
    { input_tokens: 10, output_tokens: 2, input_tokens_details: { cached_tokens: -1 } },
  ]) assert.equal(Object.hasOwn(mapResponsesUsage(usage), 'totalTokens'), false);
});
