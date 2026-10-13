import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import { CheckpointStore } from './checkpoint.mjs';
import { CheckpointRunner } from './checkpoint-runner.mjs';

const require = process.env.DSH_CHECKPOINT_TEST_MODULES ? createRequire(pathToFileURL(join(process.env.DSH_CHECKPOINT_TEST_MODULES, '_checkpoint_test.cjs'))) : createRequire(import.meta.url);
let available = true;
try { require.resolve('@deepseek-ai/dsh-agent-loop'); require.resolve('@deepseek-ai/dsh-subagent'); }
catch { available = false; }
const load = name => import(pathToFileURL(require.resolve(`@deepseek-ai/${name}`)).href);

test('real public SubagentRuntime and AgentLoop execute DAG with a local mock LLM only', { skip: !available && 'DSH kernel dependencies absent', timeout: 10000 }, async t => {
  const [{ Context, Service }, { default: LlmRuntime, LlmAdapter }, { default: SessionStore }, { default: SessionProjections }, { default: SystemPrompt }, { default: Tools }, { default: Agents }, { default: AgentLoop }, { default: Subagents }, { tryLockExclusive }] = await Promise.all([
    load('cordis'), load('dsh-llm'), load('dsh-session'), load('dsh-session-projection'), load('dsh-system-prompt'), load('dsh-tools'), load('dsh-agent'), load('dsh-agent-loop'), load('dsh-subagent'), load('node-addon-system/flock'),
  ]);
  const home = await mkdtemp(join(tmpdir(), 'dsh-checkpoint-service-'));
  const ctx = new Context();
  let runner;
  t.after(async () => {
    await runner?.close();
    await ctx.fiber.dispose();
    assert.equal(await realpath(home), home);
    assert.match(home, /\/dsh-checkpoint-service-[^/]+$/);
    await rm(home, { recursive: true });
  });
  for (const plugin of [LlmRuntime, SessionStore, SessionProjections, SystemPrompt, Tools, Agents]) await ctx.plugin(plugin);
  class Directory extends Service {
    constructor(context) { super(context, 'workingDirectory'); }
    get() { return home; }
    async ensure(_agent, signal) { signal?.throwIfAborted(); return home; }
    async set(_agent, cwd, signal) { signal?.throwIfAborted(); assert.equal(cwd, home); return home; }
  }
  await ctx.plugin(Directory);
  await ctx.plugin(AgentLoop, { agents: [] });
  await ctx.plugin(Subagents);
  const starts = ctx.subagents.startActivation.bind(ctx.subagents);
  ctx.subagents.startActivation = async spec => {
    try { return await starts(spec); }
    catch (error) { t.diagnostic(String(error.stack ?? error)); throw error; }
  };
  const requests = [];
  class LocalMock extends LlmAdapter {
    async *stream(options) {
      options.signal?.throwIfAborted();
      requests.push(options);
      const text = `mock result ${requests.length}`;
      yield { type: 'block-start', index: 0, blockType: 'text' };
      yield { type: 'text-delta', index: 0, text };
      yield { type: 'block-end', index: 0, block: { type: 'text', text } };
      yield { type: 'usage', usage: { inputTokens: 10, outputTokens: 5 } };
      yield { type: 'finish', reason: { kind: 'stop' } };
    }
  }
  ctx.llm.registerAdapter(['checkpoint-mock'], new LocalMock());
  ctx.subagents.registerProvider({ name: 'spawn', inheritsParentContext: false, capabilities: { agentOptions: true, outputSchema: true, depthLimit: true, toolFilter: true, persona: true }, prepareContinuable: async () => ({}) });
  const parent = await ctx.agentLoop.create('checkpoint-root', { provider: 'checkpoint-mock', model: 'local-only' }, { cwd: home });
  const store = await new CheckpointStore(home, tryLockExclusive).init();
  runner = new CheckpointRunner(ctx, store);
  const created = await runner.create({ id: 'service', graph: { nodes: [
    { id: 'one', deps: [], provider: 'checkpoint-mock', model: 'local-only', prompt: 'local fixture one' },
    { id: 'two', deps: ['one'], provider: 'checkpoint-mock', model: 'local-only', prompt: 'local fixture two' },
  ] } }, parent);
  assert.equal(requests.length, 0);
  await runner.activate('start', created.id, created.revision, parent, new AbortController().signal);
  await runner.wait(created.id);
  const result = await runner.status(created.id, parent, 'two');
  assert.equal(result.status, 'completed', JSON.stringify(result));
  assert.equal(requests.length, 2);
  assert.match(JSON.stringify(requests[1].messages), /mock result 1/);
  assert.equal(result.nodes[1].result.text, 'mock result 2');
  assert.equal(ctx.agents.list().length, 1);
});
