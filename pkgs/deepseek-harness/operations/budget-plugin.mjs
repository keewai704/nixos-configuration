import { join } from 'node:path';
import z from '@deepseek-ai/schemastery';
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths';
import { BudgetLedger } from './budget.mjs';
import { createBudgetPolicy } from './budget-policy.mjs';

export const name = 'budget-policy';
export const inject = ['llm', 'subagents', 'sessions', 'sessionPersistence'];
export const Config = z.object({ limits: z.any().default({}), routes: z.any().default({}) });

export async function apply(ctx, config) {
  if (typeof ctx.subagents.registerAdmission !== 'function') throw new Error('Budget policy requires the awaited subagent admission contract');
  const ledger = new BudgetLedger(join(resolveDshHome(), 'operations', 'budget.sqlite'));
  const policy = createBudgetPolicy(ctx, ledger, config);
  ctx.effect(() => () => policy.close());
  ctx.provide('budgetPolicy', policy);
  ctx.on('agent/created', async ({ agent }) => { await policy.bindSession(agent.session.header); });
  ctx.on('agent/request', (request, next) => policy.request(request, next));
  ctx.on('llm/stream', (options, next) => policy.stream(options, next));
  ctx.on('tools/execute', (exec, next) => policy.tool(exec, next));
  ctx.subagents.registerAdmission(request => policy.admitChild(request));
}
