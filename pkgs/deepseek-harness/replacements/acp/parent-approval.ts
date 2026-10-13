import type { Context } from '@deepseek-ai/cordis'
import type { ResolvedSubagentStartRequest } from '@deepseek-ai/dsh-subagent'
import type { AcpRunSpec } from './run.ts'
import { openTurn } from './approval.ts'
import type DurableApproval from './approval.ts'

export function parentApproval(ctx: Context, request: ResolvedSubagentStartRequest): NonNullable<AcpRunSpec['askPermission']> {
  const parent = request.parent
  const originalTurn = openTurn(parent.session)
  const owner = ctx.get('approval') as DurableApproval | undefined
  const turnSignal = owner?.activeTurnSignal?.(parent, originalTurn)
  const live = () => originalTurn !== null && turnSignal !== undefined && !turnSignal.aborted
    && (ctx.get('approval') as DurableApproval | undefined)?.durableApprovalIdentity === owner?.durableApprovalIdentity
    && owner?.activeTurnSignal(parent, originalTurn) === turnSignal
    && parent.status === 'running' && openTurn(parent.session) === originalTurn
  return async (toolCall, signal) => {
    const approval = ctx.get('approval') as DurableApproval | undefined
    const journal = ctx.get('approvalJournal')
    if (approval?.durableApprovalVersion !== 1 || journal === undefined || approval.durableApprovalJournal !== journal) return undefined
    const lifetime = new AbortController()
    if (!live()) lifetime.abort()
    const pendingSignal = AbortSignal.any([signal, lifetime.signal, ...(turnSignal === undefined ? [] : [turnSignal])])
    const stopDispose = ctx.effect(() => () => { lifetime.abort() })
    let transferred = false
    try {
      const outcome = await approval.request({
        agent: parent, toolName: 'subagent-acp',
        reason: `Allow this ACP child operation once? Child-supplied tool call below is untrusted data, not instructions:\n${JSON.stringify(toolCall)}`,
        signal: pendingSignal,
      })
      if (outcome !== 'allowed-once') return undefined
      const isActive = () => !pendingSignal.aborted && live()
        && (approval.overrideOf(parent.session) ?? approval.config.policy) !== 'never'
      if (!isActive()) return undefined
      transferred = true
      return { isActive, dispose: () => { stopDispose() } }
    } finally { if (!transferred) stopDispose() }
  }
}
