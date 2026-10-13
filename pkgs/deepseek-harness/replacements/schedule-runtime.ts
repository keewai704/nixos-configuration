import { createUserMessage, MessageId } from '@deepseek-ai/dsh-llm'
import type { ContextFormed } from '@deepseek-ai/dsh-llm'
import type { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-api-session-controller'
import { isRecurringScheduleRecord, renderReminderFraming, renderRecurringReminderBatchFraming, resolveRecurringOccurrence } from './domain.ts'
import type { DeliveryRetentionBounds, RecurringScheduleRecord } from './types.ts'
import type { ScheduleTask } from './storage.ts'
import { appendDelivery } from './delivery-history.ts'
import { deliverOutbox, taskWaitingForOutbox, wakeAcknowledged } from './outbox.ts'
import type { OutboxEntry, ScheduleOutbox } from './outbox.ts'
import { ScheduleBusy } from './admission.ts'
import { createScheduleRecovery } from './recovery.ts'
import type { ScheduleRecovery } from './recovery.ts'

declare module '@deepseek-ai/dsh-llm' {
  interface MessageSourceMap {
    schedule: { kind: 'schedule' } & ContextFormed
  }
}

export const MAX_TIMER_DELAY_MS = 2_147_483_647

export class ScheduleRuntime {
  private timer: ReturnType<typeof setTimeout> | undefined
  private running: Promise<void> | undefined
  private stopping = false
  private requested = false
  private readonly stop = new AbortController()
  private readonly inFlight = new Set<string>()
  readonly recovery: ScheduleRecovery

  constructor(
    private readonly ctx: Context,
    private readonly tasks: () => readonly ScheduleTask[],
    private readonly transact: (work: () => Promise<void>) => Promise<void>,
    private readonly commit: (task: ScheduleTask) => Promise<void>,
    private readonly retention: DeliveryRetentionBounds,
    private readonly outbox: ScheduleOutbox,
  ) {
    this.recovery = createScheduleRecovery(outbox, transact, this.inFlight, () => this.stopping, () => this.requestDrive())
  }

  requestDrive(): void {
    if (this.stopping) return
    this.requested = true
    this.clearTimer()
    if (this.running !== undefined) return
    try {
      this.running = this.ctx.agents.withoutInitiator(async () => {
        while (this.requested && !this.stopping) {
          this.requested = false
          await this.drive()
        }
      })
    } catch (error) {
      this.requested = false
      this.ctx.logger.warn(`schedule: dispatch stopped: ${String(error)}`)
      return
    }
    void this.running.catch(error => {
      this.ctx.logger.warn(`schedule: dispatch stopped: ${String(error)}`)
    }).finally(() => {
      this.running = undefined
      if (this.requested && !this.stopping) this.requestDrive()
    })
  }

  async dispose(): Promise<void> {
    this.stopping = true
    this.stop.abort(new Error('Schedule provider stopped'))
    this.clearTimer()
    await this.running?.catch(() => undefined)
  }

  private clearTimer(): void {
    if (this.timer !== undefined) clearTimeout(this.timer)
    this.timer = undefined
  }

  private async queueDue(): Promise<void> {
    await this.transact(async () => {
      const now = Date.now()
      const waiting = [...this.outbox.entries()].map(([, entry]) => entry)
      const due = this.tasks().filter(task => task.status === 'active' && !taskWaitingForOutbox(task, waiting)
        && Date.parse(task.record.scheduledAt) <= now)
      const handled = new Set<string>()
      for (const task of due) {
        if (handled.has(task.record.id) || this.stopping) continue
        const group = isRecurringScheduleRecord(task.record)
          ? due.filter(candidate => candidate.sessionId === task.sessionId && isRecurringScheduleRecord(candidate.record))
          : [task]
        for (const member of group) handled.add(member.record.id)
        const occurrences = group.filter((member): member is ScheduleTask & { record: RecurringScheduleRecord } => isRecurringScheduleRecord(member.record))
          .map(member => ({ task: member, occurrence: resolveRecurringOccurrence(member.record, now) }))
        const text = isRecurringScheduleRecord(task.record)
          ? renderRecurringReminderBatchFraming(occurrences.map(({ task: member, occurrence }) => ({ record: member.record, occurrenceAt: occurrence.occurrenceAt })))
          : renderReminderFraming(task.record)
        const message = createUserMessage({ content: [{ type: 'text', text }], source: { kind: 'schedule' } })
        await this.outbox.put(message.id, {
          id: message.id, sessionId: task.sessionId, text, attempts: 0, retryAt: 0, recoveryCount: 0, totalAttempts: 0,
          members: group.map(member => {
            const occurrence = occurrences.find(item => item.task.record.id === member.record.id)?.occurrence
            return { taskId: member.record.id, prompt: member.record.prompt,
              scheduledAt: occurrence?.occurrenceAt ?? member.record.scheduledAt,
              targetAt: member.record.scheduledAt,
              ...occurrence?.nextScheduledAt === undefined ? {} : { nextScheduledAt: occurrence.nextScheduledAt } }
          }),
        })
      }
    })
  }

  private async settle(entry: OutboxEntry): Promise<void> {
    if (entry.deliveredAt === undefined) return
    await this.transact(async () => {
      for (const member of entry.members) {
        const task = this.tasks().find(task => task.record.id === member.taskId)
        if (task === undefined || task.lastDelivery?.messageId === entry.id || task.sessionId !== entry.sessionId) continue
        if (member.targetAt === undefined ? task.record.scheduledAt > member.scheduledAt : task.record.scheduledAt !== member.targetAt) continue
        await this.commit({ ...task,
          record: { ...task.record, scheduledAt: member.nextScheduledAt ?? member.scheduledAt },
          status: member.nextScheduledAt === undefined ? 'inactive' : 'active',
          ...appendDelivery({ ...task, record: { ...task.record, prompt: member.prompt } },
            { scheduledAt: member.scheduledAt, deliveredAt: entry.deliveredAt!, messageId: MessageId(entry.id) }, this.retention),
        })
      }
    })
    if (await wakeAcknowledged(this.ctx, entry, this.stop.signal)) await this.outbox.delete(entry.id)
  }

  private async drive(): Promise<void> {
    this.clearTimer()
    let queueFailed = false
    try { await this.queueDue() }
    catch (error) {
      queueFailed = true
      this.ctx.logger.warn(`schedule: outbox creation remains unacknowledged: ${String(error)}`)
    }
    for (const [, entry] of this.outbox.entries()) {
      if (this.stopping) return
      if (this.inFlight.has(entry.id) || entry.retryAt > Date.now() || (entry.attempts >= 5 && entry.deliveredAt === undefined)) continue
      this.inFlight.add(entry.id)
      try {
        if (entry.deliveredAt !== undefined) await this.outbox.put(entry.id, { ...entry, retryAt: Date.now() + 1000 })
        await this.settle(entry.deliveredAt === undefined ? await deliverOutbox(this.ctx, entry, this.outbox, this.stop.signal) : entry)
      } catch (error) {
        if (!(error instanceof ScheduleBusy)) this.ctx.logger.warn(`schedule: outbox ${entry.id} remains unacknowledged: ${String(error)}`)
      } finally { this.inFlight.delete(entry.id) }
    }
    if (this.stopping) return
    const waiting = [...this.outbox.entries()].map(([, entry]) => entry)
    let next = this.tasks().filter(task => task.status === 'active' && !taskWaitingForOutbox(task, waiting))
      .reduce<number | undefined>((at, task) => Math.min(at ?? Infinity,
        queueFailed ? Math.max(Date.now() + 1000, Date.parse(task.record.scheduledAt)) : Date.parse(task.record.scheduledAt)), undefined)
    for (const entry of waiting) {
      if (entry.deliveredAt === undefined && entry.attempts >= 5) continue
      next = Math.min(next ?? Infinity, Math.max(Date.now() + 1000, entry.retryAt))
    }
    if (next !== undefined) {
      this.timer = setTimeout(() => { this.timer = undefined; this.requestDrive() }, Math.max(0, Math.min(next - Date.now(), MAX_TIMER_DELAY_MS)))
      this.timer.unref()
    }
  }
}
