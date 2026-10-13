import { afterEach, expect, it, vi } from 'vitest'
import { createUserMessage, MessageId } from '@deepseek-ai/dsh-llm'
import { SessionId } from '@deepseek-ai/dsh-session'
import { harness } from './harness.ts'
import { MemoryMediaPool } from './memory-backend.ts'
import { createScheduleRecovery } from '../schedule/recovery.ts'
import type { ScheduleObligation } from '../schedule/recovery.ts'
import { outboxSchema } from '../schedule/outbox.ts'
import type { OutboxEntry, ScheduleOutbox } from '../schedule/outbox.ts'

function clock(): void {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-09-16T00:00:00Z'))
}
afterEach(() => vi.useRealTimers())
const retry = (entry: ScheduleObligation) => ({ id: entry.id, expectedRevision: entry.revision,
  confirmation: `RETRY DELIVERY ${entry.id} ${entry.revision}` })
const entry = (overrides: Partial<OutboxEntry> = {}): OutboxEntry => ({ id: 'stable-recovery-id', sessionId: SessionId('recovery'),
  text: 'private immutable reminder', attempts: 5, retryAt: 0,
  members: [{ taskId: 'task', prompt: 'private immutable reminder', scheduledAt: '2026-09-16T00:00:00.000Z' }], ...overrides })
function poolFor(row: OutboxEntry): MemoryMediaPool {
  const pool = new MemoryMediaPool()
  pool.versions.set('schedule', 1)
  pool.media.set('schedule', { global: null, tables: new Map([
    ['tasks', new Map()], ['outbox', new Map([[row.id, structuredClone(row)]])],
  ]) })
  return pool
}

it('lists redacted obligations and durably rearms an exhausted identity across restarts', async () => {
  clock()
  const row = entry()
  const pool = poolFor(row)
  const first = await harness({ schedule: true, pool })
  const inventory = await first.ctx.scheduleRecovery.list()
  expect(inventory.version).toBe(1)
  expect(inventory.obligations).toHaveLength(1)
  const observed = inventory.obligations[0]!
  expect(observed).toMatchObject({ id: row.id, attempts: 5, totalAttempts: 5, recoveryCount: 0, inFlight: false, retryable: true })
  expect(JSON.stringify(inventory)).not.toContain('private immutable')
  await first.ctx.fiber.dispose()
  const second = await harness({ schedule: true, pool, resolveAgent: () => new Promise(() => {}) })
  expect((await second.ctx.scheduleRecovery.list()).obligations[0]?.revision).toBe(observed.revision)
  const recovered = await second.ctx.scheduleRecovery.retry(retry(observed))
  expect(recovered).toMatchObject({ id: row.id, attempts: 0, totalAttempts: 5, recoveryCount: 1 })
  expect(recovered.revision).not.toBe(observed.revision)
  await vi.advanceTimersByTimeAsync(0)
  expect([...pool.media.get('schedule')!.tables.get('outbox')!.values()]).toMatchObject([{ ...row, attempts: 1, retryAt: Date.now() + 1000, recoveryCount: 1, totalAttempts: 6 }])
  await second.ctx.fiber.dispose()
  const third = await harness({ schedule: true, pool })
  const saved = (await third.ctx.scheduleRecovery.list()).obligations[0]!
  expect(saved.recoveryCount).toBe(1)
  expect(saved.totalAttempts).toBe(6)
  await expect(third.ctx.scheduleRecovery.retry(retry(observed))).rejects.toMatchObject({ code: 'stale_revision' })
})

it.each(['accepted', 'canceled', 'pending'] as const)('manual recovery preserves %s Session evidence without duplicate replay', async state => {
  clock()
  const row = entry()
  const test = await harness({ schedule: true, pool: poolFor(row) })
  const agent = await test.create(row.sessionId)
  const message = { ...createUserMessage({ content: [{ type: 'text', text: row.text }], source: { kind: 'schedule' } }), id: MessageId(row.id) }
  if (state === 'accepted') {
    agent.followup(message)
    await agent.whenIdle()
  } else {
    agent.send(message, 'next-turn', false)
    if (state === 'canceled') agent.inbox.remove(message.id)
  }
  const before = test.adapter.requests.length
  const observed = (await test.ctx.scheduleRecovery.list()).obligations[0]!
  await test.ctx.scheduleRecovery.retry(retry(observed))
  await vi.advanceTimersByTimeAsync(1000)
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(before + Number(state === 'pending'))
  expect((await test.ctx.scheduleRecovery.list()).obligations).toEqual([])
})

it('refuses retry while the fifth attempt is still unresolved', async () => {
  clock()
  const row = entry({ attempts: 4 })
  const test = await harness({ schedule: true, pool: poolFor(row), resolveAgent: () => new Promise(() => {}) })
  await vi.advanceTimersByTimeAsync(0)
  const observed = (await test.ctx.scheduleRecovery.list()).obligations[0]!
  expect(observed).toMatchObject({ attempts: 5, inFlight: true, retryable: false })
  await expect(test.ctx.scheduleRecovery.retry(retry(observed))).rejects.toMatchObject({ code: 'in_flight' })
  expect(observed.totalAttempts).toBe(5)
})

it('requires exact phrase and revision, serializes competing confirmations, and caps operator generations', async () => {
  const rows = new Map<string, OutboxEntry>([['stable-recovery-id', entry()]])
  const outbox: ScheduleOutbox = {
    entries: () => rows.entries(), put: async (id, value) => { rows.set(id, outboxSchema.parse(value)) },
    delete: async id => rows.delete(id),
  }
  let chain = Promise.resolve()
  const transact = (work: () => Promise<void>): Promise<void> => {
    const next = chain.then(work)
    chain = next.catch(() => {})
    return next
  }
  const drive = vi.fn()
  const api = createScheduleRecovery(outbox, transact, new Set(), () => false, drive)
  const observed = (await api.list()).obligations[0]!
  await expect(api.retry({ ...retry(observed), confirmation: 'yes' })).rejects.toMatchObject({ code: 'invalid_request' })
  await expect(api.retry({ ...retry(observed), expectedRevision: 'a'.repeat(64), confirmation: `RETRY DELIVERY ${observed.id} ${'a'.repeat(64)}` })).rejects.toMatchObject({ code: 'stale_revision' })
  const results = await Promise.allSettled([api.retry(retry(observed)), api.retry(retry(observed))])
  expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1)
  expect(results.filter(result => result.status === 'rejected')).toHaveLength(1)
  expect(drive).toHaveBeenCalledOnce()
  rows.set(observed.id, entry({ recoveryCount: 100, totalAttempts: 505 }))
  const limited = (await api.list()).obligations[0]!
  expect(limited.retryable).toBe(false)
  await expect(api.retry(retry(limited))).rejects.toMatchObject({ code: 'recovery_limit' })
})

it('refunds proven busy attempts in both counters after a manual recovery', async () => {
  clock()
  const test = await harness({ schedule: true, pool: poolFor(entry()) })
  const agent = await test.create('recovery')
  const release = Promise.withResolvers<void>()
  const held = agent.runMaintenance(() => release.promise)
  try {
    const observed = (await test.ctx.scheduleRecovery.list()).obligations[0]!
    await test.ctx.scheduleRecovery.retry(retry(observed))
    await vi.advanceTimersByTimeAsync(10_000)
    expect((await test.ctx.scheduleRecovery.list()).obligations[0]).toMatchObject({ attempts: 0, totalAttempts: 5, recoveryCount: 1 })
    expect(test.adapter.requests).toHaveLength(0)
  } finally { release.resolve(); await held }
  await vi.advanceTimersByTimeAsync(1000)
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('retains recovery ownership during a durable rearm write and refuses a second concurrent retry', async () => {
  const row = entry()
  const rows = new Map([[row.id, row]])
  const written = Promise.withResolvers<void>()
  const gate = Promise.withResolvers<void>()
  const api = createScheduleRecovery({ entries: () => rows.entries(), put: async (id, value) => {
    written.resolve()
    await gate.promise
    rows.set(id, value)
  }, delete: async () => false }, work => work(), new Set(), () => false, () => {})
  const observed = (await api.list()).obligations[0]!
  const first = api.retry(retry(observed))
  await written.promise
  expect((await api.list()).obligations[0]).toMatchObject({ inFlight: true, retryable: false })
  await expect(api.retry(retry(observed))).rejects.toMatchObject({ code: 'in_flight' })
  gate.resolve()
  await first
  expect((await api.list()).obligations[0]).toMatchObject({ attempts: 0, totalAttempts: 5, recoveryCount: 1, inFlight: false })
})

it('a rejected recovery write keeps the same revision and does not authorize another attempt', async () => {
  const row = entry()
  const rows = new Map([[row.id, row]])
  const drive = vi.fn()
  const lock = new Set<string>()
  const api = createScheduleRecovery({ entries: () => rows.entries(), put: async () => { throw new Error('disk full') }, delete: async () => false },
    work => work(), lock, () => false, drive)
  const observed = (await api.list()).obligations[0]!
  await expect(api.retry(retry(observed))).rejects.toThrow('disk full')
  expect((await api.list()).obligations[0]).toEqual(observed)
  expect(lock.size).toBe(0)
  expect(drive).not.toHaveBeenCalled()
})

it('recovery counters preserve legacy compatibility but reject inconsistent provenance', () => {
  expect(outboxSchema.parse(entry()).attempts).toBe(5)
  for (const value of [entry({ recoveryCount: 1 }), entry({ totalAttempts: 5 }), entry({ recoveryCount: 0, totalAttempts: 6 }),
    entry({ recoveryCount: 101, totalAttempts: 505 }), entry({ recoveryCount: 2, totalAttempts: 4 }), entry({ recoveryCount: 2, totalAttempts: 9 })]) {
    expect(outboxSchema.safeParse(value).success).toBe(false)
  }
})
