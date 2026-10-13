import { createHash } from 'node:crypto'
import { z } from 'zod'
import type { OutboxEntry, ScheduleOutbox } from './outbox.ts'

export interface ScheduleObligation {
  id: string
  sessionId: string
  revision: string
  attempts: number
  totalAttempts: number
  recoveryCount: number
  retryAt: number
  deliveredAt?: string
  inFlight: boolean
  retryable: boolean
  members: { taskId: string; scheduledAt: string; nextScheduledAt?: string }[]
}

export interface ScheduleRecovery {
  list(): Promise<{ version: 1; obligations: ScheduleObligation[] }>
  retry(request: { id: string; expectedRevision: string; confirmation: string }): Promise<ScheduleObligation>
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    scheduleRecovery: ScheduleRecovery
  }
}

export class ScheduleRecoveryError extends Error {
  constructor(readonly code: 'invalid_request' | 'not_found' | 'stale_revision' | 'not_exhausted' | 'in_flight' | 'recovery_limit' | 'stopping') {
    super(`Schedule delivery recovery refused: ${code}`)
    this.name = 'ScheduleRecoveryError'
  }
}

const retrySchema = z.object({
  id: z.string().min(1),
  expectedRevision: z.string().regex(/^[a-f0-9]{64}$/),
  confirmation: z.string(),
}).strict()

function revisionOf(entry: OutboxEntry): string {
  return createHash('sha256').update(JSON.stringify([
    entry.id, entry.sessionId, entry.text, entry.attempts, entry.retryAt, entry.deliveredAt,
    entry.recoveryCount ?? 0, entry.totalAttempts ?? entry.attempts,
    entry.members.map(member => [member.taskId, member.prompt, member.scheduledAt, member.nextScheduledAt, member.targetAt]),
  ])).digest('hex')
}

function view(entry: OutboxEntry, inFlight: boolean): ScheduleObligation {
  const recoveryCount = entry.recoveryCount ?? 0
  return {
    id: entry.id, sessionId: entry.sessionId, revision: revisionOf(entry), attempts: entry.attempts,
    totalAttempts: entry.totalAttempts ?? entry.attempts, recoveryCount, retryAt: entry.retryAt,
    ...entry.deliveredAt === undefined ? {} : { deliveredAt: entry.deliveredAt },
    inFlight, retryable: entry.attempts === 5 && entry.deliveredAt === undefined && !inFlight && recoveryCount < 100,
    members: entry.members.map(member => ({ taskId: member.taskId, scheduledAt: member.scheduledAt,
      ...member.nextScheduledAt === undefined ? {} : { nextScheduledAt: member.nextScheduledAt } })),
  }
}

export function createScheduleRecovery(
  outbox: ScheduleOutbox,
  transact: (work: () => Promise<void>) => Promise<void>,
  inFlight: Set<string>,
  stopping: () => boolean,
  requestDrive: () => void,
): ScheduleRecovery {
  return {
    async list() {
      if (stopping()) throw new ScheduleRecoveryError('stopping')
      return { version: 1, obligations: [...outbox.entries()].map(([, entry]) => view(entry, inFlight.has(entry.id)))
        .sort((left, right) => left.retryAt - right.retryAt || left.id.localeCompare(right.id)) }
    },
    async retry(request) {
      const decoded = retrySchema.safeParse(request)
      if (!decoded.success) throw new ScheduleRecoveryError('invalid_request')
      const { id, expectedRevision, confirmation } = decoded.data
      if (confirmation !== `RETRY DELIVERY ${id} ${expectedRevision}`) throw new ScheduleRecoveryError('invalid_request')
      let result: ScheduleObligation | undefined
      await transact(async () => {
        if (stopping()) throw new ScheduleRecoveryError('stopping')
        const entry = [...outbox.entries()].find(([key]) => key === id)?.[1]
        if (entry === undefined) throw new ScheduleRecoveryError('not_found')
        if (inFlight.has(id)) throw new ScheduleRecoveryError('in_flight')
        if (revisionOf(entry) !== expectedRevision) throw new ScheduleRecoveryError('stale_revision')
        if (entry.attempts !== 5 || entry.deliveredAt !== undefined) throw new ScheduleRecoveryError('not_exhausted')
        if ((entry.recoveryCount ?? 0) >= 100) throw new ScheduleRecoveryError('recovery_limit')
        inFlight.add(id)
        try {
          const recovered: OutboxEntry = { ...entry, attempts: 0, retryAt: 0,
            recoveryCount: (entry.recoveryCount ?? 0) + 1, totalAttempts: entry.totalAttempts ?? entry.attempts }
          await outbox.put(id, recovered)
          result = view(recovered, false)
        } finally { inFlight.delete(id) }
      })
      requestDrive()
      if (result === undefined) throw new Error('Schedule recovery transaction did not produce a result')
      return result
    },
  }
}
