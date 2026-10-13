import z from '@deepseek-ai/schemastery';
import { defineTool } from '@deepseek-ai/dsh-tools';
import { checkpointToolOptions } from './checkpoint-runner.mjs';

export const name = 'checkpoint-tools';
export const inject = ['tools', 'checkpoints'];
export const Config = z.object({});

export function apply(ctx) {
  const tool = defineTool(checkpointToolOptions(ctx.checkpoints));
  ctx.effect(() => ctx.tools.register(tool));
}
