import { jsonRoute, OperationError } from './core.mjs';

export function registerBudgetRoutes(ctx) {
  const policy = ctx.budgetPolicy;
  const roots = async () => {
    const result = [];
    for (const agent of ctx.agents.list().slice(0, 1000)) {
      if (agent.session.header.parentSession !== undefined) continue;
      await policy.bindSession(agent.session.header);
      result.push(policy.snapshot(agent.id));
      if (result.length === 100) break;
    }
    return result;
  };
  const post = (handler, requireIdle = false) => jsonRoute('POST', async (input, request) => {
    let origin;
    try { origin = new URL(request.headers.get('origin')); } catch { throw new OperationError('Same-origin operator request required', 403); }
    if (!['https:', 'http:'].includes(origin.protocol) || origin.origin !== request.headers.get('origin') || origin.host !== request.headers.get('host')) throw new OperationError('Same-origin operator request required', 403);
    const site = request.headers.get('sec-fetch-site');
    if (site !== null && site !== 'same-origin') throw new OperationError('Cross-origin action rejected', 403);
    const agent = ctx.agents.get(input.rootSessionId);
    if (!agent || agent.session.header.parentSession !== undefined) throw new OperationError('Select an existing live root session', 409);
    const id = agent.id;
    await policy.bindSession(agent.session.header);
    if (ctx.agents.get(id) !== agent) throw new OperationError('Root session changed', 409);
    if (requireIdle && agent.status !== 'idle') throw new OperationError('Wait for the owning root to become idle before changing its budget', 409);
    request.signal.throwIfAborted();
    try { return await handler(input); }
    catch (error) { throw new OperationError(error.message, 409); }
  });
  const routes = [
    { path: '/api/operations/budgets', methods: ['GET'], requestBody: 'buffered', fetch: jsonRoute('GET', async () => ({ capabilities: policy.capabilities(), roots: await roots() })) },
    { path: '/api/operations/budgets/configure', methods: ['POST'], requestBody: 'buffered', fetch: post(input => policy.configure(input), true) },
    { path: '/api/operations/budgets/reconcile', methods: ['POST'], requestBody: 'buffered', fetch: post(input => policy.reconcile(input)) },
  ];
  for (const route of routes) ctx.effect(() => ctx.connection.fetch.register(route));
}
