import type { Context } from '@deepseek-ai/cordis'
import type { Agent } from '@deepseek-ai/dsh-agent'
import { createUserMessage, MessageId } from '@deepseek-ai/dsh-llm'
import type { ContextFormed, UserMessage } from '@deepseek-ai/dsh-llm'
import type { Session } from '@deepseek-ai/dsh-session'
import type { ProjectionDefinition } from '@deepseek-ai/dsh-session-projection'
import { z } from 'zod'

const pulseKind = 'keewai-schedule-wake'

declare module '@deepseek-ai/dsh-llm' {
  interface MessageSourceMap {
    'keewai-schedule-wake': { kind: 'keewai-schedule-wake' } & ContextFormed
  }
}

const stateSchema = z.object({
  inherited: z.number().int().min(0),
  claims: z.array(z.string()),
  queues: z.object({ 'next-turn': z.array(z.string()), 'next-step': z.array(z.string()) }),
  deliveries: z.record(z.string(), z.enum(['pending', 'claimed', 'accepted', 'canceled'])),
})
type DeliveryState = z.infer<typeof stateSchema>

declare module '@deepseek-ai/dsh-session-projection' {
  interface SessionProjectionStateMap {
    keewaiScheduleDelivery: DeliveryState
  }
}

export const deliveryProjection: ProjectionDefinition<'keewaiScheduleDelivery'> = {
  key: 'keewaiScheduleDelivery', stateSchema, stateVersion: 1,
  init: (_header, inherited) => ({ inherited, claims: [], queues: { 'next-turn': [], 'next-step': [] }, deliveries: {} }),
  apply(state, event) {
    const own = event.seq >= state.inherited
    if (event.type === 'turn/start') return { ...state, claims: [] }
    if (event.type === 'turn/end' && own && (event.data.reason.kind === 'aborted' || event.data.reason.kind === 'blocked')) {
      const deliveries = { ...state.deliveries }
      for (const id of state.claims) if (deliveries[id] === 'claimed') deliveries[id] = 'canceled'
      return { ...state, deliveries, claims: [] }
    }
    if (event.type === 'agent/inbox/spliced') {
      const splice = event.data
      const queue = state.queues[splice.target]
      const removed = queue.slice(splice.start, splice.start + (splice.removedCount ?? 0))
      const deliveries = { ...state.deliveries }
      for (const id of removed) {
        if (deliveries[id] !== undefined && deliveries[id] !== 'accepted') {
          deliveries[id] = splice.outcome === 'canceled' ? 'canceled' : 'claimed'
        }
      }
      for (const message of splice.inserted) {
        if (own && message.source.kind === 'schedule') deliveries[message.id] = 'pending'
      }
      return { ...state, deliveries,
        claims: splice.outcome === 'canceled' ? state.claims : [...state.claims, ...removed.filter(id => deliveries[id] === 'claimed')],
        queues: {
        ...state.queues,
        [splice.target]: queue.toSpliced(splice.start, splice.removedCount ?? 0, ...splice.inserted.map(message => message.id)),
      } }
    }
    if (own && event.type === 'user/message' && event.data.source.kind === 'schedule') {
      return { ...state, deliveries: { ...state.deliveries, [event.data.id]: 'accepted' } }
    }
    return state
  },
}

export function deliveryState(ctx: Context, session: Session, id: string): DeliveryState['deliveries'][string] | undefined {
  const state = ctx.sessionProjections.stateOf(session, 'keewaiScheduleDelivery')
  if (state === undefined) throw new Error('Schedule delivery projection is unavailable')
  return state.deliveries[id]
}

export async function checkpoint(ctx: Context, session: Session): Promise<void> {
  if (!await ctx.sessions.flush(session)) throw new Error('Schedule Session persistence did not acknowledge the checkpoint')
}

export function installAdmission(ctx: Context): void {
  ctx.sessionProjections.register(deliveryProjection)
  ctx.on('agent/created', async ({ agent }) => {
    for (const message of [...agent.inbox.nextTurn, ...agent.inbox.nextStep]) {
      if (message.source.kind === pulseKind) agent.inbox.remove(message.id)
    }
    return undefined
  }, { global: true })
  ctx.on('agent/pre-step', async (_payload, next) => {
    const decision = await next()
    return decision.kind === 'reject' ? decision : { ...decision, messages: decision.messages.filter(message => message.source.kind !== pulseKind) }
  }, { global: true })
  ctx.on('llm/stream', (options, next) => (async function* () {
    if (options.sessionId !== undefined) {
      const session = ctx.sessions.get(options.sessionId)
      if (session !== undefined) await checkpoint(ctx, session)
    }
    options.signal?.throwIfAborted()
    yield* next()
  })(), { global: true })
  ctx.on('tools/execute', async (exec, next) => {
    if (exec.agent !== undefined && exec.parent === undefined) await checkpoint(ctx, exec.agent.session)
    exec.signal.throwIfAborted()
    return next()
  }, { global: true })
}

export function abortable<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) {
    void promise.catch(() => {})
    return Promise.reject(signal.reason)
  }
  return new Promise((resolve, reject) => {
    const abort = (): void => { reject(signal.reason) }
    signal.addEventListener('abort', abort, { once: true })
    void promise.then(resolve, reject).finally(() => signal.removeEventListener('abort', abort))
  })
}

export class ScheduleBusy extends Error {}

export async function inMaintenance<T>(agent: Agent, signal: AbortSignal, operation: (signal: AbortSignal) => Promise<T>, waitForIdle = true): Promise<T> {
  for (;;) {
    signal.throwIfAborted()
    let work: Promise<T>
    try {
      work = agent.runMaintenance(maintenanceSignal => operation(AbortSignal.any([signal, maintenanceSignal])))
    } catch {
      if (!waitForIdle) throw new ScheduleBusy('Schedule target has active work')
      await abortable(agent.whenIdle(), signal)
      continue
    }
    return work
  }
}

export async function admit(ctx: Context, agent: Agent, message: UserMessage, signal: AbortSignal, waitForIdle = true): Promise<'pending' | 'accepted' | 'canceled'> {
  return inMaintenance(agent, signal, async heldSignal => {
    heldSignal.throwIfAborted()
    const state = deliveryState(ctx, agent.session, message.id)
    if (state === 'accepted' || state === 'canceled') {
      await checkpoint(ctx, agent.session)
      return state
    }
    const pending = [...agent.inbox.nextTurn, ...agent.inbox.nextStep].some(item => item.id === message.id)
    if (!pending) agent.send(message, 'next-turn', false)
    await checkpoint(ctx, agent.session)
    heldSignal.throwIfAborted()
    const current = deliveryState(ctx, agent.session, message.id)
    if (current === 'canceled') return current
    const pulse = createUserMessage({ content: [], source: { kind: pulseKind } })
    agent.send(pulse, 'next-turn', true)
    agent.inbox.remove(MessageId(pulse.id))
    await checkpoint(ctx, agent.session)
    return 'pending'
  }, waitForIdle)
}
