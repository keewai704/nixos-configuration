import { afterEach, expect, it, vi } from 'vitest'
import { SessionId } from '@deepseek-ai/dsh-session'
import { harness } from './harness.ts'
import MemorySessions from './memory-sessions.ts'
import { MemoryMediaPool } from './memory-backend.ts'

function fakeClock(): void {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-09-16T00:00:00Z'))
}
afterEach(() => vi.useRealTimers())

it('refuses an outbox key and identity mismatch before scheduling', async () => {
  const pool = new MemoryMediaPool()
  pool.versions.set('schedule', 1)
  pool.media.set('schedule', { global: null, tables: new Map([
    ['tasks', new Map()],
    ['outbox', new Map([['wrong', { id: 'right', sessionId: 'disposable', text: 'x', attempts: 0, retryAt: 0,
      members: [{ taskId: 'task', prompt: 'x', scheduledAt: '2026-09-16T00:00:00.000Z' }] }]])],
  ]) })
  await expect(harness({ schedule: true, pool })).rejects.toThrow('differs from entry id')
})

it('retries failed outbox creation without waking any unjournaled input', async () => {
  fakeClock()
  const test = await harness({ schedule: true })
  const agent = await test.create('outbox-create-failure')
  await test.service!.create(agent.id, { title: 'Retry', prompt: 'Journal before send', after_seconds: 1 })
  test.pool.failNextWrites = 1
  await vi.advanceTimersByTimeAsync(1000)
  expect(test.adapter.requests).toHaveLength(0)
  await vi.advanceTimersByTimeAsync(1000)
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('recovers durable pending input after restart when the outbox receipt write failed', async () => {
  fakeClock()
  const first = await harness({ schedule: true })
  const agent = await first.create('receipt-restart')
  const record = await first.service!.create(agent.id, { title: 'One', prompt: 'Exactly one', after_seconds: 1 })
  let count = 0
  first.flush.mockImplementation(async () => {
    await first.ctx.sessionPersistence.flush()
    count += 1
    if (count === 2) first.pool.failNextWrites = 1
  })
  await vi.advanceTimersByTimeAsync(1000)
  expect(first.adapter.requests).toHaveLength(1)
  expect((await first.service!.catalog())[0]?.status).toBe('active')
  const stored = (first.ctx.sessionPersistence as MemorySessions).rows.get(agent.id)!
  const seed = structuredClone(stored.durable)
  await first.ctx.fiber.dispose()
  const second = await harness({ schedule: true, pool: first.pool })
  await second.create(agent.id, { seed })
  await vi.advanceTimersByTimeAsync(1000)
  expect(second.adapter.requests).toHaveLength(0)
  expect((await second.service!.catalog())[0]).toMatchObject({ id: record.id, status: 'inactive' })
  expect(second.pool.media.get('schedule')?.tables.get('outbox')?.size).toBe(0)
})

it('bounds failed resolution retries across restart and retains the envelope', async () => {
  fakeClock()
  const first = await harness({ schedule: true })
  await first.service!.create(SessionId('missing'), { title: 'Retry', prompt: 'Bounded retry', after_seconds: 1 })
  await vi.advanceTimersByTimeAsync(4000)
  expect(first.resolve).toHaveBeenCalledTimes(3)
  await first.ctx.fiber.dispose()
  const second = await harness({ schedule: true, pool: first.pool })
  await vi.advanceTimersByTimeAsync(1_000_000)
  expect(second.resolve).toHaveBeenCalledTimes(2)
  expect([...second.pool.media.get('schedule')?.tables.get('outbox')?.values() ?? []]).toMatchObject([{ attempts: 5 }])
  await vi.advanceTimersByTimeAsync(1_000_000)
  expect(second.resolve).toHaveBeenCalledTimes(2)
})

it('settles a partially acknowledged recurring batch idempotently after restart', async () => {
  fakeClock()
  const first = await harness({ schedule: true })
  const agent = await first.create('batch')
  const a = await first.service!.create(agent.id, { title: 'A', prompt: 'A', every_seconds: 300 })
  const b = await first.service!.create(agent.id, { title: 'B', prompt: 'B', every_seconds: 300 })
  let changes = 0
  first.ctx.on('schedule/changed', () => {
    if (++changes === 1) first.pool.failNextWrites = 1
  })
  await vi.advanceTimersByTimeAsync(300_000)
  expect(first.adapter.requests).toHaveLength(1)
  expect((await first.service!.catalog()).filter(task => task.lastDelivery)).toHaveLength(1)
  const stored = (first.ctx.sessionPersistence as MemorySessions).rows.get(agent.id)!
  const seed = structuredClone(stored.durable)
  await first.ctx.fiber.dispose()
  const second = await harness({ schedule: true, pool: first.pool })
  await second.create(agent.id, { seed })
  await vi.advanceTimersByTimeAsync(1000)
  const catalog = await second.service!.catalog()
  expect(catalog).toEqual(expect.arrayContaining([a, b].map(record => expect.objectContaining({ id: record.id, scheduledAt: '2026-09-16T00:10:00.000Z', lastDelivery: expect.anything() }))))
  expect(second.adapter.requests).toHaveLength(0)
})

it('preserves an enqueued prompt through content edits before retry', async () => {
  fakeClock()
  const test = await harness({ schedule: true })
  const agent = await test.create('immutable')
  const record = await test.service!.create(agent.id, { title: 'Original', prompt: 'Original queued prompt', every_seconds: 300 })
  test.flush.mockRejectedValueOnce(new Error('flush failed'))
  await vi.advanceTimersByTimeAsync(300_000)
  expect(test.adapter.requests).toHaveLength(0)
  expect(await test.service!.update({ sessionId: agent.id, id: record.id, expected: record, prompt: 'Edited future prompt' })).toMatchObject({ updated: true })
  await vi.advanceTimersByTimeAsync(1000)
  expect(test.adapter.requests).toHaveLength(1)
  expect(await test.service!.history({ sessionId: agent.id, id: record.id, limit: 100 })).toMatchObject({ records: [{ prompt: 'Original queued prompt' }] })
  expect((await test.service!.catalog())[0]?.prompt).toBe('Edited future prompt')
})

it('defers a busy target beyond five retry windows without consuming failure attempts or holding management locks', async () => {
  fakeClock()
  const test = await harness({ schedule: true })
  const agent = await test.create('long-busy')
  const release = Promise.withResolvers<void>()
  const held = agent.runMaintenance(() => release.promise)
  const record = await test.service!.create(agent.id, { title: 'Original', prompt: 'Pending', after_seconds: 1 })
  await vi.advanceTimersByTimeAsync(200_000)
  expect(test.adapter.requests).toHaveLength(0)
  expect([...test.pool.media.get('schedule')?.tables.get('outbox')?.values() ?? []]).toMatchObject([{ attempts: 0 }])
  expect(await test.service!.update({ sessionId: agent.id, id: record.id, expected: record, title: 'Edited while busy' })).toMatchObject({ updated: true })
  const other = await test.service!.create(agent.id, { title: 'Disposable', prompt: 'Never due', after_seconds: 500 })
  expect(await test.service!.delete({ sessionId: agent.id, id: other.id })).toMatchObject({ deleted: true })
  release.resolve()
  await held
  await vi.advanceTimersByTimeAsync(1000)
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('does not hold the management mutex while resolving a due Session', async () => {
  fakeClock()
  const test = await harness({ schedule: true })
  const agent = await test.create('resolver-lock')
  const resolving = Promise.withResolvers<{ agent: typeof agent }>()
  test.resolve.mockImplementationOnce(() => resolving.promise)
  const record = await test.service!.create(agent.id, { title: 'Original', prompt: 'Queued', after_seconds: 1 })
  await vi.advanceTimersByTimeAsync(1000)
  expect(test.resolve).toHaveBeenCalledOnce()
  expect(await test.service!.update({ sessionId: agent.id, id: record.id, expected: record, title: 'No lock inversion' })).toMatchObject({ updated: true })
  resolving.resolve({ agent })
  await vi.advanceTimersByTimeAsync(0)
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('persists in-flight attempt charges before unresolved admission across repeated restarts', async () => {
  fakeClock()
  const pool = new MemoryMediaPool()
  for (let attempt = 1; attempt <= 5; attempt++) {
    const test = await harness({ schedule: true, pool, resolveAgent: () => new Promise(() => {}) })
    if (attempt === 1) await test.service!.create(SessionId('unresolved'), { title: 'Crash bounded', prompt: 'No uncharged startup', after_seconds: 1 })
    await vi.advanceTimersByTimeAsync(1000)
    expect(test.resolve).toHaveBeenCalledOnce()
    expect([...pool.media.get('schedule')?.tables.get('outbox')?.values() ?? []]).toMatchObject([{ attempts: attempt }])
    await test.ctx.fiber.dispose()
    vi.setSystemTime(Date.now() + 60_000)
  }
  const exhausted = await harness({ schedule: true, pool })
  await vi.advanceTimersByTimeAsync(1_000_000)
  expect(exhausted.resolve).not.toHaveBeenCalled()
})

it('stops a blocked resolver without awaiting its never-settling promise', async () => {
  fakeClock()
  const test = await harness({ schedule: true })
  test.resolve.mockImplementation(() => new Promise(() => {}))
  await test.service!.create(SessionId('parked'), { title: 'Stop', prompt: 'Stop', after_seconds: 1 })
  await vi.advanceTimersByTimeAsync(1000)
  expect(test.resolve).toHaveBeenCalledOnce()
  expect([...test.pool.media.get('schedule')?.tables.get('outbox')?.values() ?? []]).toMatchObject([{ attempts: 1 }])
  await test.ctx.fiber.dispose()
})
