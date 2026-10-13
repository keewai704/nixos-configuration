import { changePrivacy, jsonRoute, OperationError, persistencePolicy, privacySnapshot, retentionPreview } from './core.mjs';

import z from '@deepseek-ai/schemastery';

export const Config = z.object({ persistence: z.union(['launch-reset', 'profile', 'unknown']).default('unknown') });
export const name = 'operations';
export const inject = ['connection', 'loader', 'configEditor', 'sessionPersistence'];

export function apply(ctx) {
  async function inventory() {
    const entries = [...ctx.loader.entries()].filter(entry => !entry.options.group).map(entry => ({
      id: entry.id, patchId: entry.options.id, module: entry.options.name,
      enabled: !entry.disabled, phase: ['pending', 'loading', 'active', 'failed', 'disposed', 'unloading'][entry.fiber?.state] ?? 'unmounted',
    }));
    const manager = ctx.get('pluginManager');
    const bundles = manager ? (await manager.listBundles()).map(row => ({
      name: row.name, version: row.version, official: row.official, enabled: row.enabled,
      installed: row.installed, availability: row.availability, optional: row.optional,
      readOnlyReason: row.readOnlyReason, error: row.error?.code, declaredRows: row.rows.length,
    })) : [];
    return { entries, bundles, managementAvailable: Boolean(manager), trust: 'Plugins execute with host-user privileges, outside tool sandboxes. Official, installed, enabled and active are independent states. Peer-version acceptance is not a compatibility test.' };
  }

  const routes = [
    ['/api/operations/status', 'GET', async () => ({
      version: 1, privacy: privacySnapshot(ctx), persistence: persistencePolicy(ctx), inventory: await inventory(),
      reliability: { workflowJournal: Boolean(ctx.get('workflowJournal')), maintenance: 'offline-exclusive-lock', deletionInBrowser: false },
    })],
    ['/api/operations/workflows', 'GET', async () => ({ runs: await ctx.get('workflowJournal')?.list() ?? [], replayAvailable: false, interruptedMeaning: 'Journal ownership was lost; execution and side effects may still be active. Verify before a new run.' })],
    ['/api/operations/privacy', 'POST', input => changePrivacy(ctx, input)],
    ['/api/operations/retention', 'POST', async input => retentionPreview(await ctx.sessionPersistence.list(), input.days)],
    ['/api/operations/recovery', 'POST', async input => {
      const manager = ctx.get('pluginManager');
      if (!manager) throw new OperationError('Plugin management is unavailable', 409);
      if (typeof input.id !== 'string' || input.confirmation !== `DISABLE ${input.id}`) throw new OperationError('Explicit disable confirmation is required');
      const row = (await manager.listPlugins()).find(row => row.entryId === input.id);
      if (!row || !['failed', 'pending'].includes(row.fiberPhase) || row.readOnlyReason) throw new OperationError('Only an addressable failed or pending plugin can be disabled here', 409);
      return { ...await manager.setPluginEnabled(input.id, false), persistence: persistencePolicy(ctx) };
    }],
  ];
  for (const [path, method, handler] of routes) {
    ctx.effect(() => ctx.connection.fetch.register({
      path, methods: [method], requestBody: 'buffered',
      fetch: jsonRoute(method, async (input, request) => {
        try { return await handler(input, request); }
        catch (error) {
          if (!(error instanceof OperationError)) ctx.logger.error('Operations request failed', error);
          throw error;
        }
      }),
    }));
  }
}
