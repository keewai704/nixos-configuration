import { Context } from '@deepseek-ai/cordis'
import { PtcRuntime } from '@deepseek-ai/dsh-ptc-runtime'
import type { PtcBindingFunction, PtcRunRequest, PtcRunResult, PtcRunSpec } from '@deepseek-ai/dsh-ptc-runtime'
import SandboxPolicy from '@deepseek-ai/dsh-sandbox-policy'
import Subagents from '@deepseek-ai/dsh-subagent'
import { provideWorkingDirectoryFixture } from '@deepseek-ai/dsh-agent-loop-testkit'
import { SessionId } from '@deepseek-ai/dsh-session'
import { expect, it, vi } from 'vitest'
import Workflow from '../workflow/index.ts'
import type { Config } from '../workflow/index.ts'
import type { WorkflowJournal } from '../workflow/journal.ts'
import { WorkflowAdmission } from '../workflow/admission.ts'
import { harness } from './harness.ts'

const completed: PtcRunResult = { logs: [], value: { value: null, stopReason: 'completed', agentsStarted: 0 } }
class ControlledRuntime extends PtcRuntime {
  language = 'typescript'
  readonly isolation = 'process'
  execute: (spec: PtcRunSpec) => Promise<PtcRunResult> = async () => completed
  resolve(request: PtcRunRequest): PtcRunSpec {
    return { ...request, cwd: request.cwd ?? process.cwd(), timeoutMs: request.timeoutMs ?? 120_000 }
  }
  run(spec: PtcRunSpec): Promise<PtcRunResult> { return this.execute(spec) }
}
async function setup(execute?: (bindings: Record<string, PtcBindingFunction>, spec: PtcRunSpec) => Promise<PtcRunResult>, config: Config = {}) {
  const test = await harness()
  const { ctx } = test
  await ctx.plugin(SandboxPolicy, { mode: 'read-only' })
  provideWorkingDirectoryFixture(ctx)
  await ctx.plugin(Subagents)
  ctx.subagents.registerProvider({
    name: 'mock-only', inheritsParentContext: false,
    capabilities: { agentOptions: true, outputSchema: true, depthLimit: false, toolFilter: false, persona: false },
    start: async () => ({ id: SessionId('mock-child'), result: Promise.resolve({ output: [], stopReason: 'completed' }), dispose: async () => {} }),
  })
  await ctx.plugin(ControlledRuntime)
  const runtime = ctx.ptcRuntime as ControlledRuntime
  if (execute) runtime.execute = spec => execute(spec.bindings[0]!.functions, spec)
  await ctx.plugin(Workflow, { provider: 'mock-only', ...config })
  const parent = await test.create('workflow-parent')
  const start = () => ctx.workflowEngine.start({ script: 'return null', meta: { name: 'test', description: 'mock-only workflow' }, parent })
  return { ctx, parent, start, runtime }
}

it('uses unchanged WorkflowEngine.start request and gates execution and final result on journal writes', async () => {
  const begin = Promise.withResolvers<void>()
  const finish = Promise.withResolvers<void>()
  const execute = vi.fn(async () => completed)
  const { ctx, start } = await setup(execute)
  const journal: WorkflowJournal = { start: vi.fn(() => begin.promise), update: async () => {}, finish: vi.fn(() => finish.promise) }
  ctx.provide('workflowJournal', journal)
  const run = start()
  await new Promise(resolve => setImmediate(resolve))
  expect(journal.start).toHaveBeenCalledOnce()
  expect(execute).not.toHaveBeenCalled()
  begin.resolve()
  await new Promise(resolve => setImmediate(resolve))
  expect(execute).toHaveBeenCalledOnce()
  let settled = false
  void run.result.then(() => { settled = true })
  await Promise.resolve()
  expect(settled).toBe(false)
  finish.resolve()
  expect((await run.result).stopReason).toBe('completed')
  await run.dispose()
})

it('fails closed before child startup on journal reservation failure and records no prompt', async () => {
  const { ctx, start } = await setup(async bindings => {
    await bindings.startChild!({ prompt: 'private mock prompt' })
    return completed
  })
  const update = vi.fn(async () => { throw new Error('disk full') })
  ctx.provide('workflowJournal', { start: async () => {}, update, finish: async () => {} })
  const child = vi.spyOn(ctx.subagents, 'startActivation')
  const run = start()
  expect((await run.result).stopReason).not.toBe('completed')
  expect(child).not.toHaveBeenCalled()
  expect(JSON.stringify(update.mock.calls)).not.toContain('private mock prompt')
  await run.dispose()
})

it('reports final journal failure and requires the journal when configured', async () => {
  const { ctx, start } = await setup(undefined, { requireJournal: true })
  expect(start).toThrow('journal is required')
  ctx.provide('workflowJournal', { start: async () => {}, update: async () => {}, finish: async () => { throw new Error('disk full') } })
  const run = start()
  expect(await run.result).toMatchObject({ stopReason: 'error', error: expect.stringContaining('journal settlement failed') })
  await run.dispose()
})

it('applies a finite configured deadline without extending WorkflowStartRequest', async () => {
  const { start } = await setup(async (_bindings, spec) => {
    expect(spec.timeoutMs).toBeGreaterThan(0)
    expect(spec.timeoutMs).toBeLessThanOrEqual(25)
    await new Promise<void>(resolve => spec.signal!.addEventListener('abort', () => resolve(), { once: true }))
    return completed
  }, { timeoutMs: 25 })
  const run = start()
  expect(await run.result).toMatchObject({ stopReason: 'cancelled', error: expect.stringContaining('deadline') })
  await run.dispose()
})

it('inherits the root budget deadline even when the background script never starts a child', async () => {
  const { ctx, start } = await setup(async (_bindings, spec) => {
    expect(spec.timeoutMs).toBeLessThanOrEqual(30)
    await new Promise<void>(resolve => spec.signal!.addEventListener('abort', () => resolve(), { once: true }))
    return completed
  }, { timeoutMs: 1000 })
  ctx.provide('budgetPolicy', { snapshot: () => ({ limits: { deadlineAt: Date.now() + 30 } }) })
  const run = start()
  expect(await run.result).toMatchObject({ stopReason: 'cancelled', agentsStarted: 0, error: expect.stringContaining('deadline') })
  await run.dispose()
})

it('refuses invalid or expired budget deadline before publication', async () => {
  const { ctx, start } = await setup()
  ctx.provide('budgetPolicy', { snapshot: () => ({ limits: { deadlineAt: 0 } }) })
  expect(start).toThrow('root budget deadline')
})

it('retains uncertain child reservations and reports failure when cleanup rejects', async () => {
  const { ctx, start } = await setup(async bindings => {
    const child = await bindings.startChild!({ prompt: 'mock child' })
    await bindings.disposeChild!(child)
    await expect(bindings.startChild!({ prompt: 'must not start' })).rejects.toThrow('cleanup')
    return completed
  }, { maxConcurrentAgents: 1 })
  const dispose = vi.fn(async () => { throw new Error('child remains alive') })
  const spawn = vi.spyOn(ctx.subagents, 'startActivation').mockResolvedValue({ childId: SessionId('uncertain-child'),
    result: Promise.resolve({ output: [], stopReason: 'completed' }), dispose })
  const journal: WorkflowJournal = { start: vi.fn(async () => {}), update: vi.fn(async () => {}), finish: vi.fn(async () => {}) }
  ctx.provide('workflowJournal', journal)
  const run = start()
  expect(await run.result).toMatchObject({ stopReason: 'error', error: expect.stringContaining('cleanup') })
  expect(spawn).toHaveBeenCalledOnce()
  expect(dispose).toHaveBeenCalledOnce()
  expect(journal.finish).not.toHaveBeenCalled()
  expect(journal.update).toHaveBeenLastCalledWith(expect.objectContaining({ activeAgents: 1 }))
  await run.dispose()
})

it('retains unknown startup reservations when activation rejects without a quiescent handle', async () => {
  const { ctx, start } = await setup(async bindings => { await bindings.startChild!({ prompt: 'mock partial start' }); return completed })
  vi.spyOn(ctx.subagents, 'startActivation').mockRejectedValue(new Error('startup and reap failed'))
  const journal: WorkflowJournal = { start: async () => {}, update: vi.fn(async () => {}), finish: vi.fn(async () => {}) }
  ctx.provide('workflowJournal', journal)
  const run = start()
  expect(await run.result).toMatchObject({ stopReason: 'error', error: expect.stringContaining('startup quiescence is uncertain') })
  expect(journal.update).toHaveBeenLastCalledWith(expect.objectContaining({ agentsStarted: 1, activeAgents: 1 }))
  expect(journal.finish).not.toHaveBeenCalled()
  await run.dispose()
})

it('journals successful child disposal before returning capacity', async () => {
  const { ctx, start } = await setup(async bindings => {
    const child = await bindings.startChild!({ prompt: 'mock child' })
    await bindings.disposeChild!(child)
    return completed
  })
  const update = vi.fn(async () => {})
  ctx.provide('workflowJournal', { start: async () => {}, update, finish: async () => {} })
  const run = start()
  expect((await run.result).stopReason).toBe('completed')
  expect(update).toHaveBeenLastCalledWith(expect.objectContaining({ agentsStarted: 1, activeAgents: 0 }))
  await run.dispose()
})

it('reserves shared capacity synchronously and releases slots only once', () => {
  const admission = new WorkflowAdmission(Date.now() + 1000, 2, 1)
  const release = admission.reserve()
  expect(() => admission.reserve()).toThrow('concurrency')
  release(); release()
  admission.reserve()()
  expect(() => admission.reserve()).toThrow('total-agent')
  expect(() => new WorkflowAdmission(0, 1, 1).reserve()).toThrow('deadline')
})

it('shares inherited total limits across isolated engine instances before local child publication', async () => {
  const { ctx, parent, runtime } = await setup()
  const isolated: Context = ctx.isolate('workflowEngine')
  await isolated.plugin(Workflow, { provider: 'mock-only' })
  const provider = ctx.subagents.getProvider('mock-only')!
  Object.assign(provider, { prepareContinuable: async () => { throw new Error('fixture is not executed') } })
  const spawn = vi.spyOn(ctx.subagents, 'startActivation').mockImplementation(async spec => {
    const session = ctx.sessions.create(spec.childId!, { meta: { parentSession: parent.id } })
    const child = { ...parent, id: session.id, session }
    const nested = isolated.workflowEngine.start({ script: 'return null', meta: { name: 'nested', description: 'mock-only' }, parent: child })
    expect(await nested.result).toMatchObject({ stopReason: 'error', error: expect.stringContaining('total-agent') })
    await nested.dispose()
    return { childId: child.id, result: Promise.resolve({ output: [], stopReason: 'completed' }), dispose: async () => {} }
  })
  runtime.execute = async spec => { await spec.bindings[0]!.functions.startChild!({ prompt: 'mock child' }); return completed }
  const run = ctx.workflowEngine.start({ script: 'return null', meta: { name: 'root', description: 'mock-only' }, parent, maxTotalAgents: 1 })
  expect((await run.result).stopReason).toBe('completed')
  expect(spawn).toHaveBeenCalledOnce()
  await run.dispose()
})
