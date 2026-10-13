import { Context } from '@deepseek-ai/cordis'
import AgentRegistry from '@deepseek-ai/dsh-agent'
import type { CreateAgentOptions } from '@deepseek-ai/dsh-agent'
import AgentLoop from '@deepseek-ai/dsh-agent-loop'
import LlmRuntime from '@deepseek-ai/dsh-llm'
import SessionStore, { SessionId } from '@deepseek-ai/dsh-session'
import SessionProjections from '@deepseek-ai/dsh-session-projection'
import SystemPrompt from '@deepseek-ai/dsh-system-prompt'
import Tools from '@deepseek-ai/dsh-tools'
import Storage from '@deepseek-ai/dsh-storage'
import { DomainFacility } from '@deepseek-ai/dsh-storage-domain'
import { onTestFinished, vi } from 'vitest'
import { MockAdapter, textResponse } from './mock-adapter.ts'
import { MemoryMediaPool, MemoryStorageBackend } from './memory-backend.ts'
import Schedule from '../schedule/index.ts'
import { installAdmission } from '../schedule/admission.ts'
import MemorySessions from './memory-sessions.ts'
import JsonlSessions from '@deepseek-ai/dsh-session-persistence-jsonl'

export async function harness(options: {
  pool?: MemoryMediaPool
  schedule?: boolean
  jsonlRoot?: string
  resolveAgent?: Context['sessionController']['resolveAgent']
  script?: ConstructorParameters<typeof MockAdapter>[0]
} = {}) {
  const ctx = new Context()
  onTestFinished(async () => { await ctx.fiber.dispose() })
  await ctx.plugin(SessionStore)
  await ctx.plugin(SessionProjections)
  await ctx.plugin(AgentRegistry)
  await ctx.plugin(LlmRuntime)
  await ctx.plugin(SystemPrompt, {})
  await ctx.plugin(Tools)
  await ctx.plugin(AgentLoop, { agents: [] })
  const adapter = new MockAdapter(options.script ?? Array.from({ length: 20 }, () => textResponse('done')))
  ctx.llm.registerAdapter(['mock'], adapter)
  if (options.jsonlRoot === undefined) await ctx.plugin(MemorySessions)
  else await ctx.plugin(JsonlSessions, { root: options.jsonlRoot })
  const flush = vi.fn(async () => { await ctx.sessionPersistence.flush() })
  ctx.on('session/flush', flush)
  const resolve = vi.fn<Context['sessionController']['resolveAgent']>(options.resolveAgent ?? (async id => {
    const agent = ctx.agents.get(id)
    if (!agent) throw new Error('missing disposable test Session')
    return { agent }
  }))
  ctx.provide('sessionController', { resolveAgent: resolve } as never)
  await ctx.plugin(Storage)
  const pool = options.pool ?? new MemoryMediaPool()
  const backend = new MemoryStorageBackend(pool)
  ctx.effect(() => ctx.storage.backend.register('fixture', backend))
  ctx.effect(() => async () => { await backend.close() })
  const facility = new DomainFacility(ctx, { backend: 'fixture' })
  ctx.effect(() => {
    const unmount = ctx.storage.mount('domain', facility)
    ctx.provide('storageDomain', facility)
    return async () => { await facility.closeAll(); unmount() }
  })
  let service: Schedule | undefined
  if (options.schedule) {
    await ctx.plugin(Schedule, {})
    service = ctx.get('schedule') as unknown as Schedule
  } else installAdmission(ctx)
  const create = async (id = 'disposable', seed?: Pick<CreateAgentOptions, 'seed' | 'meta' | 'inheritedEventCount'>) => {
    const handle = await ctx.agents.create({ sessionId: SessionId(id), agentOptions: { provider: 'mock', model: 'mock' }, ...seed })
    return handle.agent
  }
  return { ctx, adapter, flush, pool, facility, resolve, service, create }
}
