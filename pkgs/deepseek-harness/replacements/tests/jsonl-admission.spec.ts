import { mkdtemp } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { expect, it } from 'vitest'
import { createUserMessage } from '@deepseek-ai/dsh-llm'
import { SessionId, SessionSeq } from '@deepseek-ai/dsh-session'
import { admit, deliveryState } from '../schedule/admission.ts'
import { harness } from './harness.ts'

it.skipIf(process.env.DSH_REPLACEMENTS_NATIVE_PEERS === undefined)('restores real JSONL after a durable claim and missing user acceptance', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-replacement-jsonl-'))
  const first = await harness({ jsonlRoot: root })
  const session = first.ctx.sessions.create(SessionId('claim-crash'))
  const message = createUserMessage({ content: [{ type: 'text', text: 'durable crash reminder' }], source: { kind: 'schedule' } })
  const handle = await first.ctx.sessionPersistence.create(session.header)
  await handle.append([
    { type: 'agent/inbox/spliced', seq: SessionSeq(0), time: 1, data: { target: 'next-turn', start: 0, inserted: [message] } },
    { type: 'turn/start', seq: SessionSeq(1), time: 2, data: { turn: 1 } },
    { type: 'agent/inbox/spliced', seq: SessionSeq(2), time: 3, data: { target: 'next-turn', start: 0, removedCount: 1, inserted: [] } },
  ])
  await handle.flush()
  await handle.close()
  await first.ctx.fiber.dispose()
  const second = await harness({ jsonlRoot: root })
  const resumed = await second.ctx.agents.resume({ resumeSessionId: SessionId('claim-crash'), agentOptions: { provider: 'mock', model: 'mock' } })
  expect(deliveryState(second.ctx, resumed.agent.session, message.id)).toBe('claimed')
  await admit(second.ctx, resumed.agent, message, new AbortController().signal)
  await resumed.agent.whenIdle()
  expect(second.adapter.requests).toHaveLength(1)
  expect(await admit(second.ctx, resumed.agent, message, new AbortController().signal)).toBe('accepted')
  const stored = await second.ctx.sessionPersistence.open(resumed.agent.id, 'read')
  const events = (await stored.read()).events
  expect(events.filter(event => event.type === 'user/message' && event.data.id === message.id)).toHaveLength(1)
  await stored.close()
  await resumed.dispose()
})
