import { join } from 'node:path';
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths';
import { tryLockExclusive } from '@deepseek-ai/node-addon-system/flock';
import { WorkflowJournal } from './journal.mjs';

export const name = 'workflow-journal';

export async function apply(ctx) {
  const journal = new WorkflowJournal(join(resolveDshHome(), 'operations', 'workflows'), tryLockExclusive);
  ctx.effect(() => () => journal.close());
  await journal.init();
  ctx.provide('workflowJournal', journal);
}
