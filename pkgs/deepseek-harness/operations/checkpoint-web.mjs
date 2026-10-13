import { randomUUID } from 'node:crypto';
import { jsonRoute, OperationError } from './core.mjs';
import { rootOwner } from './checkpoint-runner.mjs';
import { retryConfirmation, validateGraph } from './checkpoint.mjs';

export function humanCheckpointConfirmation(action, id, revision) {
  return `${action.toUpperCase()} CHECKPOINT ${id} ${revision}`;
}

function liveRoot(ctx, input) {
  if (typeof input.ownerSessionId !== 'string' || typeof input.ownerIdentity !== 'string') throw new OperationError('Live root selection and identity are required', 403);
  const parent = ctx.agents.get(input.ownerSessionId);
  const owner = rootOwner(ctx, parent);
  if (owner.rootIdentity !== input.ownerIdentity) throw new OperationError('Root identity changed; refresh before confirming', 409);
  return parent;
}

function sameOrigin(request) {
  const origin = request.headers.get('origin');
  let parsed;
  try { parsed = new URL(origin); } catch { throw new OperationError('Exact same-origin operator request required', 403); }
  const url = new URL(request.url);
  const host = request.headers.get('host') ?? (url.hostname === 'dsh.internal' ? null : url.host);
  if (!host || !['https:', 'http:'].includes(parsed.protocol) || parsed.origin !== origin || parsed.host !== host) throw new OperationError('Exact same-origin operator request required', 403);
  const site = request.headers.get('sec-fetch-site');
  if (site !== null && site !== 'same-origin') throw new OperationError('Cross-origin action rejected', 403);
}

export function registerCheckpointRoutes(ctx, runner) {
  const rootSnapshot = () => [...ctx.agents.list()].slice(0, 1000).flatMap(parent => {
    try {
      const owner = rootOwner(ctx, parent);
      return [{ id: owner.rootId, identity: owner.rootIdentity }];
    } catch { return []; }
  }).slice(0, 100);
  const guarded = handler => async (input, request) => {
    try { return await handler(input, request); }
    catch (error) {
      if (error instanceof OperationError) throw error;
      throw new OperationError(error instanceof Error && error.message.startsWith('Checkpoint:') ? error.message : 'Checkpoint action failed; refresh status and inspect local logs', 409);
    }
  };
  const routes = [
    {
      path: '/api/operations/checkpoints', methods: ['GET'], requestBody: 'buffered',
      fetch: jsonRoute('GET', guarded(async (_input, request) => {
        const query = new URL(request.url).searchParams;
        if (query.has('id')) {
          const parent = liveRoot(ctx, Object.fromEntries(query));
          return runner.status(query.get('id'), parent, query.get('nodeId') ?? undefined);
        }
        return {
          version: 1,
          runs: runner.store.list(),
          roots: rootSnapshot(),
          execution: 'Owning live root checkpoint tool requires approval; authenticated same-origin operator actions require typed confirmation and current root identity. Operator authentication is not proof of a human gesture; global approval policy is not changed.',
          resume: 'Only pending dependency-ready nodes dispatch; completed results are reused. Ambiguous nodes require RETRY run/node/attempt @revision, then explicit resume.',
          guarantees: 'Native bounded JSON DAG only; no arbitrary JavaScript continuation and no exactly-once side-effect guarantee.',
          privacy: 'Prompts and bounded text results are stored privately in operations/checkpoints.sqlite. Default listing exposes metadata only; selected owning-root status includes prompt previews.',
        };
      })),
    },
    {
      path: '/api/operations/checkpoints/action', methods: ['POST'], requestBody: 'buffered',
      fetch: jsonRoute('POST', guarded(async (input, request) => {
        sameOrigin(request);
        const allowed = ['action', 'ownerSessionId', 'ownerIdentity', 'id', 'revision', 'confirmation', 'graph', 'nodeId', 'attempt', 'retryConfirmation'];
        if (Object.keys(input).some(key => !allowed.includes(key))) throw new OperationError('Unknown checkpoint action field');
        if (!['create', 'start', 'resume', 'retry', 'cancel'].includes(input.action)) throw new OperationError('Unknown checkpoint action');
        const parent = liveRoot(ctx, input);
        const owner = rootOwner(ctx, parent);
        const create = input.action === 'create';
        if (!create && (!Number.isSafeInteger(input.revision) || input.revision < 1)) throw new OperationError('Current revision is required');
        if (!create) runner.store.snapshot(input.id, owner);
        const confirmation = humanCheckpointConfirmation(input.action, create ? owner.rootId : input.id, create ? 0 : input.revision);
        if (input.confirmation !== confirmation) throw new OperationError('Exact typed checkpoint confirmation is required');
        if (input.action === 'retry' && input.retryConfirmation !== retryConfirmation(input.id, input.nodeId, input.attempt, input.revision)) throw new OperationError('Exact ambiguous-attempt retry confirmation is required');
        request.signal.throwIfAborted();
        const authorization = { actor: 'authenticated-operator', action: input.action, rootId: owner.rootId };
        let result;
        if (create) result = await runner.create({ id: input.id ?? randomUUID(), graph: validateGraph(input.graph) }, parent, request.signal, authorization);
        else if (input.action === 'start' || input.action === 'resume') result = await runner.activate(input.action, input.id, input.revision, parent, request.signal, authorization);
        else if (input.action === 'retry') result = await runner.retry({ id: input.id, nodeId: input.nodeId, attempt: input.attempt, revision: input.revision, confirmation: input.retryConfirmation }, parent, request.signal, authorization);
        else result = await runner.cancel(input.id, input.revision, parent, request.signal, authorization);
        return { ...result, authorization: { ...authorization, priorRevision: create ? null : input.revision, confirmation } };
      })),
    },
  ];
  for (const route of routes) ctx.effect(() => ctx.connection.fetch.register(route));
}
