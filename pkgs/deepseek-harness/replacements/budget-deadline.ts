import type { Context } from '@deepseek-ai/cordis'
import { WorkflowError } from '@deepseek-ai/dsh-workflow'

interface RootBudgetSnapshot {
  limits: { deadlineAt?: number }
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    budgetPolicy: { snapshot(sessionId: string): RootBudgetSnapshot }
  }
}

export function budgetDeadline(ctx: Context, sessionId: string): number {
  const deadline = ctx.get('budgetPolicy')?.snapshot(sessionId).limits.deadlineAt
  if (deadline === undefined) return Infinity
  if (!Number.isSafeInteger(deadline) || deadline <= Date.now()) {
    throw new WorkflowError('workflow root budget deadline must be a future epoch millisecond', 'INVALID_ARGUMENT')
  }
  return deadline
}
