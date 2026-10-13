import { expect, it, vi } from 'vitest'
import { mountWorkingDirectoryFixture } from './working-directory-fixture.ts'
import { SessionId, SessionSeq } from '@deepseek-ai/dsh-session'
import type { Context } from '@deepseek-ai/cordis'
import type { SessionObservation } from '@deepseek-ai/dsh-session-query'
import MemorySessions from './memory-sessions.ts'
import { SubagentError, SubagentDepthError } from '@deepseek-ai/dsh-subagent'
import type { SubagentResult } from '@deepseek-ai/dsh-subagent'
import { remoteMethods } from '@deepseek-ai/dsh-typert-protocol'
import Subagents, { SubagentError as ReplacementError, SubagentDepthError as ReplacementDepthError } from '../subagents/index.ts'
import { harness } from './harness.ts'

async function setup(requireAdmission = false) {
  const test = await harness()
  await mountWorkingDirectoryFixture(test.ctx)
  await test.ctx.plugin(Subagents, { requireAdmission })
  const service = test.ctx.subagents as unknown as Subagents
  const parent = await test.create('subagents-parent')
  const start = () => service.startActivation({ provider: 'fixture', label: 'fixture', delivery: 'caller', signal: new AbortController().signal, request: { parent, prompt: [{ type: 'text', text: 'mock task' }] } })
  return { ...test, service, parent, start }
}
const caps = { agentOptions: true, outputSchema: true, depthLimit: false, toolFilter: false, persona: false }

it('preserves original public error constructors and Remote namespace', async () => {
  const { service, start } = await setup()
  expect(ReplacementError).toBe(SubagentError)
  expect(ReplacementDepthError).toBe(SubagentDepthError)
  await expect(start()).rejects.toBeInstanceOf(SubagentError)
  expect(service.typertRemote.namespace).toBe('subagents')
  expect(remoteMethods(service).length).toBeGreaterThan(0)
})

it('admits before external startup and waits for quiescent settlement', async () => {
  const test = await setup()
  const begin = Promise.withResolvers<void>()
  const finish = Promise.withResolvers<void>()
  const disposed = vi.fn(async () => {})
  const providerStart = vi.fn(async () => ({ id: SessionId('external-child'), result: Promise.resolve({ output: [], stopReason: 'completed' as const }), dispose: disposed }))
  test.service.registerProvider({ name: 'fixture', capabilities: caps, inheritsParentContext: false, start: providerStart })
  const publish = vi.fn(async () => {})
  const settle = vi.fn(async (outcome: { quiescent: boolean }) => { expect(outcome.quiescent).toBe(true); expect(disposed).toHaveBeenCalledOnce(); await finish.promise })
  test.service.registerAdmission(async () => { await begin.promise; return { publish, settle } })
  const pending = test.start()
  await new Promise(resolve => setImmediate(resolve))
  expect(providerStart).not.toHaveBeenCalled()
  begin.resolve()
  const run = await pending
  await new Promise(resolve => setImmediate(resolve))
  expect(publish).toHaveBeenCalledWith(run.childId)
  expect(settle).toHaveBeenCalledOnce()
  let done = false
  void run.result.then(() => { done = true })
  await Promise.resolve()
  expect(done).toBe(false)
  finish.resolve()
  await run.result
  await run.dispose()
  expect(settle).toHaveBeenCalledOnce()
})

it('fails closed when required admission is absent and when policy rejects', async () => {
  const test = await setup(true)
  const providerStart = vi.fn(async () => ({ id: SessionId('unused'), result: Promise.resolve({ output: [], stopReason: 'completed' as const }), dispose: async () => {} }))
  test.service.registerProvider({ name: 'fixture', capabilities: caps, inheritsParentContext: false, start: providerStart })
  await expect(test.start()).rejects.toThrow('required but unavailable')
  const release = test.service.registerAdmission(async () => { throw new Error('budget exhausted') })
  await expect(test.start()).rejects.toThrow('budget exhausted')
  release()
  await expect(test.start()).rejects.toThrow('required but unavailable')
  expect(providerStart).not.toHaveBeenCalled()
})

it('cancels published external work using the lease signal and retains uncertain cleanup', async () => {
  const test = await setup()
  const controller = new AbortController()
  const ended = Promise.withResolvers<SubagentResult>()
  const dispose = vi.fn(async () => { ended.resolve({ output: [], stopReason: 'aborted' }); throw new Error('reap failed') })
  test.service.registerProvider({ name: 'fixture', capabilities: caps, inheritsParentContext: false,
    start: async () => ({ id: SessionId('deadline-child'), result: ended.promise, dispose }) })
  const settle = vi.fn(async () => {})
  test.service.registerAdmission(async () => ({ signal: controller.signal, publish() {}, settle }))
  const run = await test.start()
  controller.abort()
  await run.result
  await expect(run.dispose()).rejects.toThrow('reap failed')
  expect(dispose).toHaveBeenCalledOnce()
  expect(settle).toHaveBeenCalledWith({ quiescent: false })
})

it('disposes an external child immediately while asynchronous lease publication remains blocked', async () => {
  const test = await setup()
  const controller = new AbortController()
  const publishing = Promise.withResolvers<void>()
  const entered = Promise.withResolvers<void>()
  const disposed = vi.fn(async () => {})
  let childSignal: AbortSignal | undefined
  test.service.registerProvider({ name: 'fixture', capabilities: caps, inheritsParentContext: false,
    start: async request => { childSignal = request.signal; return { id: SessionId('unpublished-child'), result: new Promise(() => {}), dispose: disposed } } })
  const settle = vi.fn(async () => {})
  test.service.registerAdmission(async () => ({ signal: controller.signal, publish: async () => { entered.resolve(); await publishing.promise }, settle }))
  const starting = test.start()
  const rejected = expect(starting).rejects.toThrow('deadline')
  await entered.promise
  controller.abort(new Error('deadline'))
  await new Promise(resolve => setImmediate(resolve))
  expect(childSignal?.aborted).toBe(true)
  expect(disposed).toHaveBeenCalledOnce()
  expect(settle).not.toHaveBeenCalled()
  publishing.resolve()
  await rejected
  expect(settle).toHaveBeenCalledWith({ quiescent: true })
  expect(disposed).toHaveBeenCalledOnce()
})

it('applies admission to local creation and cold continuation without provider preparation again', async () => {
  const test = await setup()
  const observeSession: Context['sessionQuery']['observeSession'] = async id => {
    const row = (test.ctx.sessionPersistence as MemorySessions).rows.get(id)!
    const result: SessionObservation = { source: 'prepared', header: row.header, inheritedEventCount: row.inherited,
      events: structuredClone(row.events), cursor: row.events.length === 0 ? -1 : SessionSeq(row.events.length - 1),
      retain: () => result, [Symbol.dispose]() {} }
    return result
  }
  test.ctx.provide('sessionQuery', { observeSession } as never)
  const prepare = vi.fn(async () => ({}))
  test.service.registerProvider({ name: 'fixture', capabilities: { ...caps, depthLimit: true, toolFilter: true, persona: true }, inheritsParentContext: false, prepareContinuable: prepare })
  const resumed: boolean[] = []
  test.service.registerAdmission(async request => { resumed.push(request.resumed); return { publish() {}, settle() {} } })
  const run = await test.start()
  expect((await run.result).stopReason).toBe('completed')
  await run.dispose()
  await test.service.sendMessage(test.parent, run.childId, [{ type: 'text', text: 'mock continuation' }], { signal: new AbortController().signal })
  await test.service.waitForChildren(test.parent)
  expect(prepare).toHaveBeenCalledOnce()
  expect(resumed).toEqual([false, true])
})
