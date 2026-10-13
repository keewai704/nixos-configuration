import { join } from 'node:path'
import type { Context } from '@deepseek-ai/cordis'
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths'
import { tryLockExclusive } from '@deepseek-ai/node-addon-system/flock'
import { ApprovalJournal } from './approval-journal.ts'
import type {} from '@deepseek-ai/dsh-client-connection'

declare module '@deepseek-ai/cordis' {
  interface Context {
    approvalJournal: ApprovalJournal
  }
}

export const name = 'approval-journal'

export async function apply(ctx: Context): Promise<void> {
  const journal = new ApprovalJournal(join(resolveDshHome(), 'operations', 'approvals'), tryLockExclusive)
  ctx.effect(() => () => journal.close())
  await journal.init()
  ctx.provide('approvalJournal', journal)
  ctx.inject(['connection'], (scope) => {
    scope.effect(() => scope.connection.fetch.register({
      path: '/api/operations/approvals', methods: ['GET'], requestBody: 'buffered',
      fetch: async () => {
        const headers = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }
        try {
          return new Response(JSON.stringify({
            version: 1, approvals: await journal.list(), audit: 'independent-durable-ledger',
            nativeAudit: 'Paired only when the original turn remains open at settlement; emergency closure is recorded solely here.',
            grantMeaning: 'An allowed-once record is durable authorization, not proof of response delivery, child execution, or side effects.',
            interruptedMeaning: 'Question ownership was lost before a final durable decision; no new grant may use this record. Execution is not replayed.',
          }), { headers })
        } catch (error) {
          scope.logger.error('Approval audit inventory failed: %o', error)
          return new Response(JSON.stringify({ error: 'Approval audit inventory unavailable' }), { status: 503, headers })
        }
      },
    }))
  })
}
