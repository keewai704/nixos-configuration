import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { expect, it } from 'vitest'
import type { Context } from '@deepseek-ai/cordis'
import type { ConnectionRpcHandler, PeerScope } from '@deepseek-ai/dsh-client-connection'
import Gateway from '@deepseek-ai/dsh-api-gateway'
import TypertRegistry from '@deepseek-ai/dsh-typert-registry'
import type { TypertContribution } from '@deepseek-ai/dsh-typert-registry'
import { SessionId } from '@deepseek-ai/dsh-session'
import Schedule from '../schedule/index.ts'
import Subagents from '../subagents/index.ts'
import { harness } from './harness.ts'
import { mountWorkingDirectoryFixture } from './working-directory-fixture.ts'

const peerRoot = process.env.DSH_REPLACEMENTS_NATIVE_PEERS
const bundleRoot = process.env.DSH_REPLACEMENTS_BUNDLE

async function descriptor(packageName: string): Promise<TypertContribution> {
  if (peerRoot === undefined) throw new Error('Strict RPC verification requires original kernel descriptors')
  const module = await import(pathToFileURL(join(peerRoot, '@deepseek-ai', packageName, 'lib/typert.host.js')).href) as { TYPERT: TypertContribution }
  expect(module.TYPERT.package).toBe(`@deepseek-ai/${packageName}`)
  expect(module.TYPERT.face).toBe('host')
  expect(module.TYPERT.invocations.every(invocation => invocation.result.mode === 'strict')).toBe(true)
  return module.TYPERT
}

async function gateway(ctx: Context) {
  let handler: ConnectionRpcHandler | undefined
  let matches: ((endpoint: string) => boolean) | undefined
  const peer: PeerScope = { id: 'replacement-rpc-operator' as PeerScope['id'], ctx, dispose: async () => {} }
  await ctx.plugin(TypertRegistry)
  ctx.provide('connection', {
    rpc: {
      intercept(channel: string, accepts: (endpoint: string) => boolean, dispatch: ConnectionRpcHandler) {
        expect(channel).toBe('/api')
        handler = dispatch
        matches = accepts
        return () => { handler = undefined; matches = undefined }
      },
    },
    requestRejection: () => undefined,
  } as never)
  await ctx.plugin(Gateway, {})
  return async (endpoint: string, args: Record<string, unknown>, signal = new AbortController().signal) => {
    expect(matches?.(endpoint)).toBe(true)
    if (handler === undefined) throw new Error('Gateway did not attach its public Connection RPC handler')
    const payload: unknown = JSON.parse(JSON.stringify({ args }))
    const result = await handler(endpoint, payload, signal, peer)
    return JSON.parse(JSON.stringify(result)) as Awaited<ReturnType<ConnectionRpcHandler>>
  }
}

it.skipIf(peerRoot === undefined)('round-trips replacement Schedule through original strict Typert descriptors and Gateway transport', async () => {
  const test = await harness()
  const Provider = bundleRoot === undefined ? Schedule
    : (await import(pathToFileURL(join(bundleRoot, 'lib/schedule.js')).href) as { default: typeof Schedule }).default
  await test.ctx.plugin(Provider, {})
  const call = await gateway(test.ctx)
  const original = await descriptor('dsh-schedule')
  const remove = test.ctx.typert.register(original)
  expect(test.ctx.typert.listPackages({ package: original.package, face: 'host' })).toHaveLength(1)
  for (const method of ['list', 'catalog', 'history', 'update', 'delete']) {
    expect(test.ctx.typert.local.get(`schedule/${method}`)?.id).toBe(`${original.package}#schedule/${method}`)
  }
  const sessionId = SessionId('strict-schedule-disposable')
  const record = await test.ctx.schedule.create(sessionId, { title: 'RPC before', prompt: 'No model request', after_seconds: 86400 })
  expect(await call('schedule/list', { request: { sessionId } })).toMatchObject({ ok: true, value: [record] })
  expect(await call('schedule/catalog', {})).toMatchObject({ ok: true, value: [{ ...record, sessionId, status: 'active' }] })
  expect(await call('schedule/history', { request: { sessionId, id: record.id, limit: 10 } })).toMatchObject({
    ok: true, value: { id: record.id, records: [], earlierRecordsUnavailable: false, earlierRecordsPruned: false, retention: { days: 30, records: 200 } },
  })
  const updated = await call('schedule/update', { request: { sessionId, id: record.id, expected: record, title: 'RPC after' } })
  expect(updated).toMatchObject({ ok: true, value: { id: record.id, updated: true, record: { ...record, title: 'RPC after' } } })
  const invalid = await call('schedule/list', { request: { sessionId: 17 } })
  expect(invalid).toMatchObject({ ok: false, error: { code: 'gateway/input-invalid' } })
  const cancelled = await call('schedule/delete', { request: { sessionId, id: record.id } }, AbortSignal.abort(new Error('fixture transport canceled')))
  expect(cancelled).toMatchObject({ ok: false, error: { code: 'gateway/cancelled' } })
  expect(await call('schedule/list', { request: { sessionId } })).toMatchObject({ ok: true, value: [{ id: record.id, title: 'RPC after' }] })
  expect(await call('schedule/delete', { request: { sessionId, id: record.id } })).toEqual({ ok: true, value: { id: record.id, deleted: true } })
  expect(await call('schedule/catalog', {})).toEqual({ ok: true, value: [] })
  await remove()
  expect(await call('schedule/list', { request: { sessionId } })).toMatchObject({ ok: false, error: { code: 'gateway/definition-unavailable' } })
  test.ctx.typert.register(original)
  expect(await call('schedule/list', { request: { sessionId } })).toEqual({ ok: true, value: [] })
  expect(test.adapter.requests).toHaveLength(0)
  expect(test.resolve).not.toHaveBeenCalled()
})

it.skipIf(peerRoot === undefined)('routes strict original subagent interrupt RPC to the replacement live manager with ownership checks', async () => {
  const test = await harness({ script: ['hang'] })
  await mountWorkingDirectoryFixture(test.ctx)
  const Provider = bundleRoot === undefined ? Subagents
    : (await import(pathToFileURL(join(bundleRoot, 'lib/subagents.js')).href) as { default: typeof Subagents }).default
  await test.ctx.plugin(Provider, {})
  const call = await gateway(test.ctx)
  const original = await descriptor('dsh-subagent')
  test.ctx.typert.register(original)
  expect(test.ctx.typert.listPackages({ package: original.package, face: 'host' })).toHaveLength(1)
  expect(test.ctx.typert.local.get('subagents/interruptByParent')?.id).toBe('@deepseek-ai/dsh-subagent#subagents/interruptByParent')
  const parent = await test.create('strict-rpc-parent')
  test.ctx.subagents.registerProvider({ name: 'rpc-local', inheritsParentContext: false,
    capabilities: { agentOptions: true, outputSchema: true, depthLimit: true, toolFilter: true, persona: true },
    prepareContinuable: async () => ({}),
  })
  const entered = Promise.withResolvers<void>()
  test.ctx.on('agent/request', async (payload, next) => {
    if (payload.agent !== parent) entered.resolve()
    return next()
  }, { global: true })
  const run = await test.ctx.subagents.startActivation({ provider: 'rpc-local', label: 'Disposable RPC child', delivery: 'caller',
    signal: new AbortController().signal, request: { parent, prompt: [{ type: 'text', text: 'Mock-only parked work' }] } })
  await entered.promise
  const args = { childSessionId: run.childId, parentSessionId: parent.id, mode: 'continuable' }
  expect(await call('subagents/interruptByParent', { ...args, mode: 'external' })).toMatchObject({ ok: false, error: { code: 'gateway/input-invalid' } })
  expect(await call('subagents/interruptByParent', { ...args, parentSessionId: 'unrelated-parent' })).toMatchObject({ ok: false, error: { code: 'subagent/unauthorized' } })
  expect(await call('subagents/interruptByParent', args)).toEqual({ ok: true, value: { accepted: true } })
  expect((await run.result).stopReason).toBe('aborted')
  await run.dispose()
  expect(await call('subagents/interruptByParent', args)).toEqual({ ok: true, value: { accepted: true } })
})
