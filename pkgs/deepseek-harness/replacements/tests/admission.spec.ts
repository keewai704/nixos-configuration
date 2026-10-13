import { expect, it, vi } from 'vitest'
import { createUserMessage, MessageId } from '@deepseek-ai/dsh-llm'
import { SessionId, SessionLogOffset, SessionSeq } from '@deepseek-ai/dsh-session'
import type { SessionEvent } from '@deepseek-ai/dsh-session'
import { remoteMethods } from '@deepseek-ai/dsh-typert-protocol'
import { ScheduleInputError } from '@deepseek-ai/dsh-schedule'
import { admit, deliveryState, inMaintenance } from '../schedule/admission.ts'
import { harness } from './harness.ts'

const signal = (): AbortSignal => new AbortController().signal
const reminder = (id = 'outbox-identity') => ({ ...createUserMessage({ content: [{ type: 'text' as const, text: 'durable reminder' }], source: { kind: 'schedule' } }), id: MessageId(id) })
const tick = (): Promise<void> => new Promise(resolve => setImmediate(resolve))

it('holds the unmodified loop until durable admission, with one real input and no pulse model input', async () => {
  const test = await harness()
  const agent = await test.create()
  const gate = Promise.withResolvers<void>()
  test.flush.mockImplementationOnce(() => gate.promise)
  const pending = admit(test.ctx, agent, reminder(), signal())
  await tick()
  expect(test.adapter.requests).toHaveLength(0)
  expect(agent.inbox.nextTurn.map(message => message.id)).toEqual(['outbox-identity'])
  gate.resolve()
  expect(await pending).toBe('pending')
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
  expect(deliveryState(test.ctx, agent.session, 'outbox-identity')).toBe('accepted')
  expect(JSON.stringify(test.adapter.requests)).not.toContain('keewai-schedule-wake')
  expect(await admit(test.ctx, agent, reminder(), signal())).toBe('accepted')
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it.each(['reject', 'false'] as const)('preserves failed %s admission without waking and retries the same pending identity', async kind => {
  const test = await harness()
  const agent = await test.create()
  const failure = vi.spyOn(test.ctx.sessions, 'flush')
  if (kind === 'reject') failure.mockRejectedValueOnce(new Error('disk unavailable'))
  else failure.mockResolvedValueOnce(false)
  await expect(admit(test.ctx, agent, reminder(), signal())).rejects.toThrow()
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(0)
  expect(agent.inbox.nextTurn.map(message => message.id)).toEqual(['outbox-identity'])
  expect(await admit(test.ctx, agent, reminder(), signal())).toBe('pending')
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('contains an unrelated buffered wake behind a failed pre-model checkpoint', async () => {
  const test = await harness()
  const agent = await test.create()
  const gate = Promise.withResolvers<void>()
  test.flush.mockImplementationOnce(() => gate.promise)
  const pending = admit(test.ctx, agent, reminder(), signal())
  await tick()
  agent.followup(createUserMessage({ content: [{ type: 'text', text: 'ordinary' }], source: { kind: 'user' } }))
  test.flush.mockRejectedValue(new Error('disk unavailable'))
  gate.reject(new Error('disk unavailable'))
  await expect(pending).rejects.toThrow('disk unavailable')
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(0)
})

it('does not revive explicit cancellation or cancellation after claim', async () => {
  const test = await harness()
  const agent = await test.create()
  agent.send(reminder(), 'next-turn', false)
  agent.inbox.remove(MessageId('outbox-identity'))
  expect(await admit(test.ctx, agent, reminder(), signal())).toBe('canceled')
  expect(test.adapter.requests).toHaveLength(0)
  const second = await test.create('claim-cancel')
  const remove = test.ctx.on('agent/pre-step', async ({ agent: current }, next) => {
    if (current === second) current.cancel({ kind: 'user' }, { keepInbox: true })
    return next()
  }, { global: true })
  await admit(test.ctx, second, reminder('claim-cancel-id'), signal())
  await second.whenIdle()
  remove()
  expect(await admit(test.ctx, second, reminder('claim-cancel-id'), signal())).toBe('canceled')
  expect(test.adapter.requests).toHaveLength(0)
})

it('restores pending and claimed crash snapshots without duplicate insertion or losing the real input', async () => {
  const message = reminder()
  const inserted: SessionEvent = { type: 'agent/inbox/spliced', seq: SessionSeq(0), time: 1, data: { target: 'next-turn', start: 0, inserted: [message] } }
  for (const claimed of [false, true]) {
    const test = await harness()
    const seed: SessionEvent[] = [inserted]
    if (claimed) seed.push(
      { type: 'turn/start', seq: SessionSeq(1), time: 2, data: { turn: 1 } },
      { type: 'agent/inbox/spliced', seq: SessionSeq(2), time: 3, data: { target: 'next-turn', start: 0, removedCount: 1, inserted: [] } },
      { type: 'turn/end', seq: SessionSeq(3), time: 4, data: { turn: 1, reason: { kind: 'interrupted' } } },
    )
    const agent = await test.create(`recovery-${claimed}`, { seed })
    expect(await admit(test.ctx, agent, message, signal())).toBe('pending')
    await agent.whenIdle()
    expect(test.adapter.requests).toHaveLength(1)
    expect(deliveryState(test.ctx, agent.session, message.id)).toBe('accepted')
  }
})

it('removes a crash-persisted inert pulse on creation without removing real pending input', async () => {
  const test = await harness()
  const real = reminder()
  const pulse = createUserMessage({ content: [], source: { kind: 'keewai-schedule-wake' } })
  const agent = await test.create('pulse-recovery', { seed: [
    { type: 'agent/inbox/spliced', seq: SessionSeq(0), time: 1, data: { target: 'next-turn', start: 0, inserted: [real, pulse] } },
  ] })
  expect(agent.inbox.nextTurn.map(message => message.id)).toEqual([real.id])
  await admit(test.ctx, agent, real, signal())
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
  expect(JSON.stringify(test.adapter.requests)).not.toContain('keewai-schedule-wake')
})

it('does not inherit another Session acceptance receipt through a fork prefix', async () => {
  const test = await harness()
  const real = reminder()
  const seed: SessionEvent[] = [{ type: 'user/message', seq: SessionSeq(0), time: 1, data: real, surfaceOp: 'append' }]
  const agent = await test.create('fork-child', { seed, meta: { isSeeded: true, parentSession: SessionId('fork-parent') }, inheritedEventCount: SessionLogOffset(1) })
  expect(deliveryState(test.ctx, agent.session, real.id)).toBeUndefined()
})

it('cancels a busy admission wait without canceling the agent or hanging disposal', async () => {
  const test = await harness()
  const agent = await test.create()
  const gate = Promise.withResolvers<void>()
  const held = agent.runMaintenance(() => gate.promise)
  const controller = new AbortController()
  const callback = vi.fn(async () => true)
  const waiting = inMaintenance(agent, controller.signal, callback)
  controller.abort(new Error('provider stopping'))
  await expect(waiting).rejects.toThrow('provider stopping')
  expect(callback).not.toHaveBeenCalled()
  gate.resolve()
  await held
})

it('does not let a later unrelated canceled turn erase a previous crash claim', async () => {
  const test = await harness()
  const message = reminder()
  const agent = await test.create('unrelated-cancel', { seed: [
    { type: 'agent/inbox/spliced', seq: SessionSeq(0), time: 1, data: { target: 'next-turn', start: 0, inserted: [message] } },
    { type: 'turn/start', seq: SessionSeq(1), time: 2, data: { turn: 1 } },
    { type: 'agent/inbox/spliced', seq: SessionSeq(2), time: 3, data: { target: 'next-turn', start: 0, removedCount: 1, inserted: [] } },
    { type: 'turn/end', seq: SessionSeq(3), time: 4, data: { turn: 1, reason: { kind: 'interrupted' } } },
    { type: 'turn/start', seq: SessionSeq(4), time: 5, data: { turn: 2 } },
    { type: 'turn/end', seq: SessionSeq(5), time: 6, data: { turn: 2, reason: { kind: 'aborted', reason: { kind: 'user' } } } },
  ] })
  expect(deliveryState(test.ctx, agent.session, message.id)).toBe('claimed')
  await admit(test.ctx, agent, message, signal())
  await agent.whenIdle()
  expect(test.adapter.requests).toHaveLength(1)
})

it('preserves public Schedule error identity, Remote decorators, and namespace', async () => {
  const test = await harness({ schedule: true })
  const service = test.service!
  expect(service.typertRemote.namespace).toBe('schedule')
  expect(remoteMethods(service).map(marker => marker.exportName ?? marker.method).sort()).toEqual(['catalog', 'delete', 'history', 'list', 'update'])
  await expect(service.create(SessionId('unused'), { title: '', prompt: 'x', after_seconds: 1 })).rejects.toBeInstanceOf(ScheduleInputError)
})
