import { createHash, randomUUID } from 'node:crypto'
import type { Context } from '@deepseek-ai/cordis'
import type { Agent } from '@deepseek-ai/dsh-agent'
import { scopeTarget } from '@deepseek-ai/dsh-scope'
import type { Session } from '@deepseek-ai/dsh-session'
import UpstreamApproval, { ApprovalRequestId } from '@deepseek-ai/dsh-user-approval'
import type { ApprovalOutcome, ApprovalRequest, Config } from '@deepseek-ai/dsh-user-approval'
import type { ApprovalAuditResult, ApprovalJournal } from './approval-journal.ts'
import type {} from './approval-journal-plugin.ts'

export function openTurn(session: Session): number | null {
  const events = session.snapshotEvents()
  for (let index = events.length - 1; index >= 0; index--) {
    const event = events[index]!
    if (event.type === 'turn/end') return null
    if (event.type === 'turn/start') return event.seq
  }
  return null
}

const outcomes: readonly ApprovalOutcome[] = ['allowed-once', 'rejected', 'cancelled', 'unavailable']

export default class DurableApproval extends UpstreamApproval {
  static inject = ['sessions', 'approvalJournal']
  readonly durableApprovalVersion = 1
  readonly durableApprovalIdentity = Symbol('durable-approval')
  readonly durableApprovalJournal: ApprovalJournal
  private readonly pending = new Set<{ request: ApprovalRequest; lifetime: AbortController; settled: Promise<void> }>()
  private disposed = false
  private readonly turns = new WeakMap<Agent, { seq: number; signal: AbortSignal }>()

  constructor(ctx: Context, config: Config) {
    super(ctx, config)
    this.durableApprovalJournal = ctx.approvalJournal
    const capture = ({ agent, turn, signal }: { agent: Agent; turn: number; signal: AbortSignal }) => {
      const seq = openTurn(agent.session)
      if (seq === null) return
      const event = agent.session.snapshotEvents()[seq]
      if (event?.type !== 'turn/start' || event.data.turn !== turn) return
      const previous = this.turns.get(agent)
      if (previous?.seq === seq && previous.signal !== signal) {
        this.turns.set(agent, { seq, signal: AbortSignal.abort() })
      } else {
        this.turns.set(agent, { seq, signal })
      }
    }
    ctx.on('agent/pre-step', (payload, next) => { capture(payload); return next() }, { prepend: true })
    ctx.on('agent/request', (payload, next) => { capture(payload); return next() }, { prepend: true })
    ctx.on('agent/turn-stopping', async ({ agent }) => {
      const pending = [...this.pending].filter(entry => entry.request.agent === agent)
      for (const entry of pending) entry.lifetime.abort()
      await Promise.all(pending.map(entry => entry.settled))
    })
    ctx.on('session/event', (session, event) => {
      if (event.type !== 'turn/end' && event.type !== 'turn/start'
        && !(event.type === 'approval/policy' && event.data.policy === 'never')) return
      for (const entry of this.pending) {
        if (entry.request.agent.session === session) entry.lifetime.abort()
      }
    })
    ctx.on('session/disposed', (session) => {
      for (const entry of this.pending) {
        if (entry.request.agent.session === session) entry.lifetime.abort()
      }
    })
    ctx.effect(() => async () => {
      this.disposed = true
      const pending = [...this.pending]
      for (const entry of pending) entry.lifetime.abort()
      await Promise.all(pending.map(entry => entry.settled))
    })
  }

  activeTurnSignal(agent: Agent, seq: number | null): AbortSignal | undefined {
    const turn = this.turns.get(agent)
    return !this.disposed && turn !== undefined && seq !== null && turn.seq === seq
      && !turn.signal.aborted && openTurn(agent.session) === seq ? turn.signal : undefined
  }

  private policy(req: ApprovalRequest): 'ask' | 'never' {
    return this.overrideOf(req.agent.session) ?? this.config.policy ?? 'ask'
  }

  private async answerRequest(req: ApprovalRequest): Promise<ApprovalOutcome> {
    if (req.signal!.aborted || this.disposed) return 'cancelled'
    if (this.policy(req) === 'never') return 'rejected'
    const signal = req.signal!
    const cancelled = Promise.withResolvers<ApprovalOutcome>()
    const abort = () => { cancelled.resolve('cancelled') }
    signal.addEventListener('abort', abort, { once: true })
    try {
      const answer = Promise.resolve().then(() => {
        if (signal.aborted || this.disposed) return 'cancelled' as const
        if (this.policy(req) === 'never') return 'rejected' as const
        return this.ctx.waterfall(scopeTarget(req.agent, req.agent), 'approval/request', req, () => Promise.resolve<ApprovalOutcome>('unavailable'))
      }).then(outcome => outcomes.includes(outcome) ? outcome : 'unavailable' as const, () => 'unavailable' as const)
      return await Promise.race([answer, cancelled.promise])
    } finally { signal.removeEventListener('abort', abort) }
  }

  override async request(req: ApprovalRequest): Promise<ApprovalOutcome> {
    const session = req.agent.session
    const turn = openTurn(session)
    const id = ApprovalRequestId(randomUUID())
    const lifetime = new AbortController()
    const signal = req.signal === undefined ? lifetime.signal : AbortSignal.any([req.signal, lifetime.signal])
    const request = { ...req, signal }
    const eligible = !signal.aborted && !this.disposed && turn !== null
    const settled = Promise.withResolvers<void>()
    const entry = { request, lifetime, settled: settled.promise }
    this.pending.add(entry)
    const journal = this.durableApprovalJournal
    const active = () => !signal.aborted && !this.disposed && turn !== null && openTurn(session) === turn
    let started = false
    let answer: ApprovalOutcome = 'unavailable'
    let nativeAudit: ApprovalAuditResult['nativeAudit'] = 'not-recorded'
    let sessionFlushed = false
    const result = (outcome: ApprovalOutcome, cause: ApprovalAuditResult['cause']): ApprovalAuditResult => ({ answer, outcome, nativeAudit, sessionFlushed, cause })
    try {
      const reason = req.reason ?? ''
      await journal.start({
        id, sessionId: session.id, turnStartSeq: turn, toolName: req.toolName,
        ...(req.callId === undefined ? {} : { callId: req.callId }),
        reasonDigest: createHash('sha256').update(reason).digest('hex'), reasonBytes: Buffer.byteLength(reason),
      })
      started = true
      answer = active() ? await this.answerRequest(request) : 'cancelled'
      let outcome: ApprovalOutcome = active() ? answer : 'cancelled'
      let cause: ApprovalAuditResult['cause'] = !active() ? turn === null || openTurn(session) !== turn ? 'closed-turn' : 'cancelled'
        : this.policy(req) === 'never' ? 'policy-never' : answer === 'unavailable' ? 'unavailable' : 'answer'
      if (this.policy(req) === 'never' && outcome === 'allowed-once') outcome = 'rejected'
      if (eligible && turn !== null && openTurn(session) === turn) {
        nativeAudit = 'failed'
        session.append('approval/asked', {
          id, toolName: req.toolName,
          ...(req.callId === undefined ? {} : { callId: req.callId }),
          ...(req.reason === undefined ? {} : { reason: req.reason }),
        })
        session.append('approval/decided', { id, outcome })
        nativeAudit = 'paired'
        sessionFlushed = await this.ctx.sessions.flush(session) === true
      }
      if (outcome === 'allowed-once' && (!sessionFlushed || nativeAudit !== 'paired')) {
        outcome = 'unavailable'
        cause = 'durability-failed'
      }
      if (outcome === 'allowed-once' && (!active() || this.policy(req) === 'never')) {
        outcome = 'cancelled'
        cause = 'cancelled'
      }
      await journal.finish(id, result(outcome, cause))
      if (await journal.flush(id) !== true) throw new Error('Approval audit durability barrier did not participate')
      if (outcome === 'allowed-once' && (!active() || this.policy(req) === 'never')) {
        outcome = 'cancelled'
        await journal.finish(id, result(outcome, 'cancelled'))
        if (await journal.flush(id) !== true) throw new Error('Approval cancellation audit did not flush')
      }
      return outcome
    } catch (error) {
      if (started) {
        try { await journal.finish(id, result('unavailable', 'durability-failed')) }
        catch (auditError) { this.ctx.logger.error('Approval audit completion failed; pending record requires owner-loss recovery: %o', auditError) }
      }
      throw error
    } finally {
      if (started) void journal.release(id).catch(error => { this.ctx.logger.error('Approval audit lease release failed: %o', error) })
      this.pending.delete(entry)
      settled.resolve()
    }
  }
}
