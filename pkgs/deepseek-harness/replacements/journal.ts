import type { WorkflowResult } from '@deepseek-ai/dsh-workflow'

export interface WorkflowJournal {
  start(record: {
    id: string
    parentSessionId: string
    name: string
    startedAt: number
    deadlineAt: number
    maxTotalAgents: number
    maxConcurrentAgents: number
  }): Promise<void>
  update(record: { id: string; agentsStarted: number; activeAgents: number }): Promise<void>
  finish(record: {
    id: string
    stopReason: WorkflowResult['stopReason']
    agentsStarted: number
    finishedAt: number
  }): Promise<void>
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    workflowJournal: WorkflowJournal
  }
}
