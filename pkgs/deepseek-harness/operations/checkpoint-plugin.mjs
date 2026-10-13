import z from '@deepseek-ai/schemastery';
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths';
import { tryLockExclusive } from '@deepseek-ai/node-addon-system/flock';
import { CheckpointStore } from './checkpoint.mjs';
import { CheckpointRunner } from './checkpoint-runner.mjs';
import { registerCheckpointRoutes } from './checkpoint-web.mjs';

export const name = 'checkpoints';
export const inject = ['subagents', 'agents', 'workingDirectory', 'llm', 'sessionProjections'];
export const Config = z.object({
  backend: z.string().default('spawn'),
  maxActiveRuns: z.number().step(1).min(1).max(16).default(4),
});

export async function apply(ctx, config = {}) {
  const store = new CheckpointStore(resolveDshHome(), tryLockExclusive);
  const runner = new CheckpointRunner(ctx, store, config);
  ctx.effect(() => () => runner.close());
  await store.init();
  ctx.provide('checkpoints', runner);
  ctx.inject(['connection'], web => registerCheckpointRoutes(web, runner));
}
