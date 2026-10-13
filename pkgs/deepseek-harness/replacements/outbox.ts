import type { Context } from '@deepseek-ai/cordis'
import { createUserMessage, MessageId } from '@deepseek-ai/dsh-llm'
import { SessionId } from '@deepseek-ai/dsh-session'
import { z } from 'zod'
import type { ScheduleTask } from './storage.ts'
import { abortable, admit, ScheduleBusy } from './admission.ts'

export const outboxSchema = z.object({
  id: z.string().min(1),
  sessionId: z.string().min(1).transform(SessionId),
  text: z.string(),
  members: z.array(z.object({
    taskId: z.string().min(1),
    prompt: z.string(),
    scheduledAt: z.string(),
    nextScheduledAt: z.string().optional(),
    targetAt: z.string().optional(),
  }).strict()).min(1),
  attempts: z.number().int().min(0).max(5),
  retryAt: z.number().int().min(0),
  deliveredAt: z.string().optional(),
  recoveryCount: z.number().int().min(0).max(100).optional(),
  totalAttempts: z.number().int().min(0).max(505).optional(),
}).strict().refine(entry => (entry.recoveryCount === undefined) === (entry.totalAttempts === undefined)
  && (entry.totalAttempts ?? entry.attempts) === 5 * (entry.recoveryCount ?? 0) + entry.attempts, 'Invalid schedule recovery counters')

export type OutboxEntry = z.infer<typeof outboxSchema>
export interface ScheduleOutbox {
  entries(): IterableIterator<[string, OutboxEntry]>
  put(key: string, value: OutboxEntry): Promise<void>
  delete(key: string): Promise<boolean>
}

async function admission(ctx: Context, entry: OutboxEntry, stop: AbortSignal): Promise<'pending' | 'accepted' | 'canceled'> {
  const signal = AbortSignal.any([stop, AbortSignal.timeout(30_000)])
  signal.throwIfAborted()
  const resolved = await abortable(ctx.sessionController.resolveAgent(entry.sessionId), signal)
  if ('error' in resolved) throw resolved.error
  const message = createUserMessage({ content: [{ type: 'text', text: entry.text }], source: { kind: 'schedule' } })
  return admit(ctx, resolved.agent, { ...message, id: MessageId(entry.id) }, signal, false)
}

export async function wakeAcknowledged(ctx: Context, entry: OutboxEntry, signal: AbortSignal): Promise<boolean> {
  try { return await admission(ctx, entry, signal) !== 'pending' }
  catch (error) { if (error instanceof ScheduleBusy) return false; throw error }
}

export async function deliverOutbox(ctx: Context, entry: OutboxEntry, outbox: ScheduleOutbox, signal: AbortSignal): Promise<OutboxEntry> {
  const recoveryCount = entry.recoveryCount ?? 0
  const totalAttempts = entry.totalAttempts ?? entry.attempts
  const attempt = { ...entry, recoveryCount, totalAttempts: totalAttempts + 1,
    attempts: entry.attempts + 1, retryAt: Date.now() + Math.min(60_000, 1000 * 2 ** entry.attempts) }
  await outbox.put(entry.id, attempt)
  try { await admission(ctx, entry, signal) }
  catch (error) {
    if (error instanceof ScheduleBusy) {
      const current = [...outbox.entries()].find(([key]) => key === entry.id)?.[1]
      if (current?.attempts === attempt.attempts && current.retryAt === attempt.retryAt && current.deliveredAt === undefined
        && current.recoveryCount === recoveryCount && current.totalAttempts === totalAttempts + 1) {
        await outbox.put(entry.id, { ...attempt, attempts: entry.attempts, totalAttempts, retryAt: Date.now() + 1000 })
      }
    }
    throw error
  }
  const receipt = { ...attempt, deliveredAt: new Date().toISOString() }
  await outbox.put(entry.id, receipt)
  return receipt
}

export function taskWaitingForOutbox(task: ScheduleTask, entries: readonly OutboxEntry[]): boolean {
  return entries.some(entry => entry.members.some(member => member.taskId === task.record.id
    && (entry.deliveredAt === undefined || task.record.scheduledAt <= member.scheduledAt)))
}
