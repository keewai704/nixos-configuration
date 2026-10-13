import { expect, it } from 'vitest'
import { remoteMethods } from '@deepseek-ai/dsh-typert-protocol'
import { ScheduleInputError } from '@deepseek-ai/dsh-schedule'
import type WorkflowType from '../workflow/index.ts'
import type ScheduleType from '../schedule/index.ts'
import type SubagentsType from '../subagents/index.ts'
import type ApprovalType from '../acp/approval.ts'
import UpstreamApproval from '@deepseek-ai/dsh-user-approval'
import { SubagentError } from '@deepseek-ai/dsh-subagent'
import { mountWorkingDirectoryFixture } from './working-directory-fixture.ts'
import { harness } from './harness.ts'

it.skipIf(process.env.DSH_REPLACEMENTS_BUNDLE === undefined)('loads compiled provider entries with preserved Remote and error identities', async () => {
  const root = process.env.DSH_REPLACEMENTS_BUNDLE!
  const compiled = await import(`${root}/lib/schedule.js`) as { default: typeof ScheduleType }
  const workflow = await import(`${root}/lib/workflow.js`) as { default: typeof WorkflowType }
  expect(workflow.default.prototype.start).toBeTypeOf('function')
  const subagents = await import(`${root}/lib/subagents.js`) as { default: typeof SubagentsType; SubagentError: typeof SubagentError }
  expect(subagents.SubagentError).toBe(SubagentError)
  const approval = await import(`${root}/lib/approval.js`) as { default: typeof ApprovalType }
  const acp = await import(`${root}/lib/acp.js`) as typeof import('../acp/index.ts')
  const journal = await import(`${root}/lib/approval-journal.js`) as typeof import('../acp/approval-journal-plugin.ts')
  expect(Object.getPrototypeOf(approval.default.prototype)).toBe(UpstreamApproval.prototype)
  expect(acp.name).toBe('reliability-acp')
  expect(acp.apply).toBeTypeOf('function')
  expect(journal.name).toBe('approval-journal')
  const test = await harness()
  await mountWorkingDirectoryFixture(test.ctx)
  await test.ctx.plugin(subagents.default, {})
  expect(test.ctx.subagents.typertRemote.namespace).toBe('subagents')
  expect(remoteMethods(test.ctx.subagents).length).toBeGreaterThan(0)
  await test.ctx.plugin(compiled.default, {})
  const service = test.ctx.schedule
  expect(service.typertRemote.namespace).toBe('schedule')
  expect(remoteMethods(service).map(marker => marker.exportName ?? marker.method).sort()).toEqual(['catalog', 'delete', 'history', 'list', 'update'])
  const agent = await test.create('compiled-test')
  await expect(service.create(agent.id, { title: '', prompt: 'x', after_seconds: 1 })).rejects.toBeInstanceOf(ScheduleInputError)
})
